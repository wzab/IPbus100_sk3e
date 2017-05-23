#!/bin/bash
coregen -r -b pkt_fifo.xco -p coregen.cgp
xtclsh sk3e_ipbus100.tcl rebuild_project

