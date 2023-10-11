#!/usr/bin/env nu

use std log

let url_base = "https://uptime.netcraft.com/perf/reports/performance/OCSP"
mut url_number = 0
mut url_suffix = ""
mut res = []

loop {
    let url = $"($url_base)($url_suffix)"
    log info $"Getting ($url)... \(pagination: ($url_number)\)"
    let dt = (http get $url)
    # log debug $dt
    let is_last_page = ($dt | query web -q 'div.pagination__next' | each { str trim } | get 0 | is-empty)
    let rows = ($dt | query web -q 'tr > td.site-link-box:nth-child(3) > a' | each { str trim })
    log debug ($rows | to json)

    $res = ($res | append $rows)
    if $is_last_page { break }

    $url_number = $url_number + 50
    $url_suffix = $"?pageoff=($url_number)"
}

log debug ($res | to json)

{
  "description" : "Firefox.app - allow OCSP queries\n\nBased on https://uptime.netcraft.com/perf/reports/performance/OCSP",
  "name" : "Firefox-Allowlist",
  "rules" : [
    {
      "action" : "allow",
      "ports" : "80",
      "process" : "\/Applications\/Firefox.app\/Contents\/MacOS\/firefox",
      "protocol" : "tcp",
      "remote-domains" : ($res | each { str replace -r '/.*' '' } | uniq | sort)
    }
  ]
}
| to json
| save -f firefox-allowlist.lsrules
