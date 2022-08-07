su - ec2-user << EOF
until [ -f .local/share/tutor/config.yml ]
do
     sleep 15
done
echo "Config file found. Executing tutor (Open edX) initialization"
/home/ec2-user/install-and-quickstart-edx.exp
exit
EOF