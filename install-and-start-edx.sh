su - ec2-user << EOF
until [ -f .local/share/tutor/config.yml ]
do
     sleep 15
done
echo "Config file found. Executing tutor (Open edX) initialization"
tutor local dc pull
tutor local start --detach
exit
EOF