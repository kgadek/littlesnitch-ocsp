#!/usr/bin/env nu

# Requires coreutils

use std log

let scriptTime = date now

def tap [genMsg: closure] {
    let input = $in
    ($input | do $genMsg)
    $input
}

#  e88~-_       e      ,d88~~\
# d888   \     d8b     8888
# 8888        /Y88b    `Y88b
# 8888       /  Y88b    `Y88b,
# Y888   /  /____Y88b     8888
#  "88_-~  /      Y88b \__88P'


def "cas hashpath" [key: string]: string -> string {
    let cas_root = $"($env.HOME)/Downloads/cas"
    let hash = $key | hash sha256
    let subdir = $cas_root | path join $"sha256-($hash | str substring 0..2)"
    mkdir $subdir
    $subdir | path join ($hash | str substring 2..)
}

def "cas write" [hashpath: string, suffix: string, condition: closure, update: closure] {
    let casFile = $hashpath + $suffix
    do $update | save -f $casFile
    $casFile
}

def "cas upsert" [hashpath: string, suffix: string, condition: closure, update: closure] -> string {
    let casFile = $hashpath + $suffix
    if (
      # No file
      (not ($casFile | path exists))
      # or refresh condition applies
      or ($casFile | do $condition)
    ) {
        do $update | save -f $casFile
    }
    $casFile
}

def "cas needs-refresh" [hashpath: string, rootSuffix: string, freshness: duration] {
  let casRootFile = $hashpath + $rootSuffix

  # No file or refresh condition applies
  let res = (not ($casRootFile | path exists)) or ($scriptTime - (ls $casRootFile | get 0.modified) > $freshness)
  $res
}

def "cas refresh" [hashpath: string, rootSuffix: string, freshness: duration, update: closure] {
    cas upsert $hashpath $rootSuffix { || ($scriptTime - (ls $in | get 0.modified) > $freshness) } $update
}

def "cas upsert-group" [hashpath: string, rootSuffix: string, condition: closure, updateRoot: closure, updateGroup: closure] {
    let casRootFile = $hashpath + $rootSuffix
    if (
      # No file
      (not ($casRootFile | path exists))
      # or refresh condition applies
      or ($casRootFile | do $condition)
    ) {
        log debug $"cas upsert-group [hashpath=($hashpath)][rootSuffix=($rootSuffix)]: updating"
        let updatedFiles = do $updateGroup | each {|row| let file = $hashpath + $row.suffix; $row.value | save -f $file; $file }
        do $updateRoot | save -f $casRootFile
        log debug $"cas upsert-group [hashpath=($hashpath)][rootSuffix=($rootSuffix)]: updated"
        [$casRootFile, ...$updatedFiles]
    } else {
        log debug $"cas upsert-group [hashpath=($hashpath)][rootSuffix=($rootSuffix)]: not updating"
        [$casRootFile]
    }
}

def "cas refresh-group" [hashpath: string, rootSuffix: string, freshness: duration, updateRoot: closure, updateGroup: closure] {
    log debug $"cas refresh-group [hashpath=($hashpath)][rootSuffix=($rootSuffix)][freshness=($freshness)]"
    cas upsert-group $hashpath $rootSuffix { || ($scriptTime - (ls $in | get 0.modified) > $freshness) } $updateRoot $updateGroup
}


# 888b    |             d8                              88~\   d8
# |Y88b   |  e88~~8e  _d88__  e88~~\ 888-~\   /~~~8e  _888__ _d88__
# | Y88b  | d888  88b  888   d888    888          88b  888    888
# |  Y88b | 8888__888  888   8888    888     e88~-888  888    888
# |   Y88b| Y888    ,  888   Y888    888    C888  888  888    888
# |    Y888  "88___/   "88_/  "88__/ 888     "88_-888  888    "88_/


def getNetcraft []: nothing -> list<string> {
  log debug "getNetcraft"
  let url_base = "https://uptime.netcraft.com/perf/reports/performance/OCSP"
  mut url_number = 0
  mut url_suffix = ""
  mut res = []

  loop {
      log debug "getNetcraft inloop"
      let url = $"($url_base)($url_suffix)"
      let hashpath = cas hashpath $url
      let pagination = $url_number

      let files = cas refresh-group $hashpath ".key.txt" 4wk { $url } {
          log debug $"getNetcraft refresh ($hashpath).key.txt"
          log info $"\(netcraft) Getting ($url)... \(pagination: ($pagination)\)"
          [{suffix: ".html", value: (http get $url)}]
      }

      let dt = open ($hashpath + ".html")
      log debug $"getNetcraft inloop dt=\(open ($hashpath + ".html"))"

      log debug $"getNetcraft inloop query is_last_page..."
      let is_last_page = $dt | query web -q 'div.pagination__next' | each { str trim } | get 0 | is-empty
      log debug $"getNetcraft inloop query rows..."
      let rows = $dt | query web -q 'tr > td.site-link-box:nth-child(3) > a' | each { str trim } | each { str replace -r '/.*' '' }
      log debug $"getNetcraft inloop is_last_page=($is_last_page) rows=($rows)"

      $res = ($res | append $rows)
      if $is_last_page { break }

      $url_number = $url_number + 50
      $url_suffix = $"?pageoff=($url_number)"
  }
  log debug "getNetcraft: done"
  $res
}

#  e88~-_  888                         888   88~\ 888
# d888   \ 888  e88~-_  888  888  e88~\888 _888__ 888   /~~~8e  888-~\  e88~~8e
# 8888     888 d888   i 888  888 d888  888  888   888       88b 888    d888  88b
# 8888     888 8888   | 888  888 8888  888  888   888  e88~-888 888    8888__888
# Y888   / 888 Y888   ' 888  888 Y888  888  888   888 C888  888 888    Y888    ,
#  "88_-~  888  "88_-~  "88_-888  "88_/888  888   888  "88_-888 888     "88___/

let reportStep = 100

def getCloudflare []: nothing -> list<string> {
  log debug "getCloudflare"
  let datasize = open cloudflare-radar-domains-top-100000-20240108-20240115.csv | length

  open cloudflare-radar-domains-top-100000-20240108-20240115.csv
  | enumerate
  | tap { log info $"Pure data \(len=($in | length))"}
  | upsert item.casPath {|domainDescription| cas hashpath $domainDescription.item.domain }
  | tap { log info $"Adding staleness data \(len=($in | length))"}
  | par-each {|domainDescription| $domainDescription | upsert item.needsRefresh { cas needs-refresh $domainDescription.item.casPath ".key.txt" 4wk } }
  | tap { log info $"Filtering those that are fresh \(len=($in | length))"}
  | where $it.item.needsRefresh == true
  | tap { log info $"Obtaining data \(len=($in | length))"}
  | par-each {|domainDescription|
      log debug $"getCloudflare: [domainDescription.item=($domainDescription.item)][casPath=($domainDescription.item.casPath)]"

      cas refresh-group $domainDescription.item.casPath ".key.txt" 4wk { $domainDescription.item.domain } {
        log info $"\(cloudflare) Getting ($domainDescription.item.domain)..."
        ""
        | timeout --preserve-status 15s openssl s_client -no-interactive -showcerts -connect $"($domainDescription.item.domain):443"
        | awk 'BEGIN {prnt=0} /-----BEGIN CERTIFICATE-----/ {prnt=1; print "-----NEXT CERT-----"; print; next} /-----END CERTIFICATE-----/ {prnt=0; print} prnt==1 { print }'
        | split row "-----NEXT CERT-----\n"
        | str trim
        | where $it != ""
        | enumerate
        | each {|cert|
            { suffix: $".cert.($cert.index).pem", value: $cert.item }
          }
      }

      if ($"($domainDescription.item.casPath).cert.0.pem" | path exists) {
          ls $"($domainDescription.item.casPath).cert.*.pem"
          | each { |certfile|
              openssl x509 -noout -ocsp_uri -in $certfile.name
              | str trim
              | lines
              | each {|line|
                  $line
                  | str trim
                  | str replace -r '^http://' ''
                  | str replace -r '/.*$' ''
                }
            }
          | flatten
      } else {
          []
      }
    }
  | flatten
}


# 888-~88e  888-~\  e88~-_   e88~~\  e88~~8e   d88~\  d88~\
# 888  888b 888    d888   i d888    d888  88b C888   C888
# 888  8888 888    8888   | 8888    8888__888  Y88b   Y88b
# 888  888P 888    Y888   ' Y888    Y888    ,   888D   888D
# 888-_88"  888     "88_-~   "88__/  "88___/  \_88P  \_88P
# 888

let res: list<string> = (
    [ { getNetcraft }, { getCloudflare } ]
  | par-each { |fn| do $fn }
  | flatten
  | where $it != ""
  | each { str downcase }
  | uniq
  | sort
)

log debug $"res=($res)"


{
  description: "Firefox.app - allow OCSP queries\n\nBased on https://uptime.netcraft.com/perf/reports/performance/OCSP and https://radar.cloudflare.com/domains",
  name: "Firefox-Allowlist",
  rules: [
    {
      action: "allow",
      ports: "80",
      process: "\/Applications\/Firefox.app\/Contents\/MacOS\/firefox",
      protocol: "tcp",
      remote-domains: $res
    }
  ]
}
| to json
| save -f firefox-allowlist.lsrules
