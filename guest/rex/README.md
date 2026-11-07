# Rex
I am running rex on the linux VM as my own user and allowing rex to create a tailscale device which we will connect to from iOS or other rex clients.

## Install Rex on Linux
```
printf '[rex]\nname=Rex (snapshot)\nbaseurl=https://pkgs.superlogical.com/rex/rpm/snapshot/$basearch\nenabled=1\ngpgcheck=1\nrepo_gpgcheck=1\ngpgkey=https://pkgs.superlogical.com/rex/keys/rex.asc\n' | sudo install -m 0644 /dev/stdin /etc/yum.repos.d/rex.repo
sudo dnf install rex
```

## Setup tailscale with Rex
I already have a tailscale account set up, so I can use that to authenticate with Rex.

Below is setting up tailscale for this VM itself, this is NOT needed, just something I did so I could access the VM if I needed to without Rex.
```
sudo dnf install tailscale
sudo systemctl enable --now tailscaled
sudo tailscale up
```

Below is creating a second tailscale connection for the Rex service itself
```
rex server tailscale on
rex server status
# I followed the URL to authenticate this to my tailscale
```

## Configure

## Setting up Rex to start on boot as my user
I am running as the user `jmatthews` and I'm using systemd to start Rex on boot as my user.

I created the below file
```
cat .config/systemd/user/rex.service
[Unit]
Description=Rex personal server

[Service]
ExecStart=/usr/bin/rex server run --tailscale --log-format text
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
```

```
sudo loginctl enable-linger jmatthews
systemctl --user daemon-reload
systemctl --user enable --now rex.service
systemctl --user status rex.service
journalctl --user -u rex -f
```
