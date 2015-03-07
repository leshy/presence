#!/bin/sh

node node_modules/browserify/bin/cmd.js -t ejsify clientside.js -o static/js/bundle.js
notify-send "new bundle ready"
rm static/js/bundle.min.js

[ -z "$1" ] || \
  node node_modules/uglify-js/bin/uglifyjs static/js/bundle.js \
    -o static/js/bundle.min.js \
    -c "dead_code=true,evaluate=true,join_vars=true,unused=true,drop_console=true" \
    -m "toplevel,sort"
