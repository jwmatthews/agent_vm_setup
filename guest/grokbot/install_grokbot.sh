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
