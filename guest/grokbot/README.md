# Grokbot headless setup
Below shows I setup GrokBot on a headless Linux VM.
My goal was to give my Linux VM to GrokBot to run commands on to explore it acting as a chief of staff over my coding agents.

## Install GrokBot

```
sudo tee /etc/yum.repos.d/grok-bot.repo <<'EOF'
[grok-bot]
name=Grok Bot
baseurl=https://downloads.cursor.com/yumrepo/grok-bot
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://downloads.cursor.com/keys/anysphere.asc
EOF

sudo dnf install grok-bot
```

## Install the headless grokbot project
* Note that the upstream version worked with an older GrokBot around ~v0.30, it didn't work with latest GrokBot. I worked with Fable 5.1 to update the code to work with latest and in process tweaked it a little work for my VM setup

## Prequisities
Need node running, I install nvm to allow future flexibility for exploring other versions of node
```
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.41.0/install.sh | bash
source ~/.bashrc
nvm
nvm install --lts
```

## Fork of grokbot-headless
* I used this commit:
 * https://github.com/jwmatthews/grokbot-headless/commit/30d49ed55093e5682a5405c5a5ecb4020f0bd8ca

```
./install.sh
.local/bin/grok-bot-headless login
.local/bin/grok-bot-headless policy always
systemctl --user start grok-bot-headless
sudo loginctl enable-linger jmatthews
```
