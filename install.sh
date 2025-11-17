#!/bin/sh
zig build install
sudo cp --force ./zig-out/bin/shot /usr/bin/shot-raw

if [ -f "/usr/bin/shot" ]; then
  sudo rm -f /usr/bin/shot
fi

sudo touch /usr/bin/shot
sudo tee /usr/bin/shot > /dev/null << 'WRAPPER_EOF'
#!/bin/sh
cmd=$(/usr/bin/shot-raw "$@" 2>/dev/tty)
eval "$cmd"
WRAPPER_EOF

sudo chmod +x /usr/bin/shot
