#!/bin/sh
zig build install
sudo cp ./zig-out/bin/shot /usr/local/bin/shot-tui

if [ -f "/usr/bin/shot" ]; then
  sudo rm -f /usr/local/bin/shot
fi

sudo touch /usr/local/bin/shot
sudo tee /usr/local/bin/shot > /dev/null << 'WRAPPER_EOF'
#!/bin/sh
cmd=$(/usr/local/bin/shot-tui "$@" 2>/dev/tty)
eval "$cmd"
WRAPPER_EOF

sudo chmod +x /usr/local/bin/shot
