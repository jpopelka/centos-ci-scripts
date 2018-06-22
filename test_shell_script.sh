set +e

export CICO_API_KEY=$(cat ~/duffy.key )

# get node
n=1
while true
do
    cico_output=$(cico node get -f value -c ip_address -c comment)
    if [ $? -eq 0 ]; then
        read CICO_hostname CICO_ssid <<< $cico_output
        if  [ ! -z "$CICO_hostname" ]; then
            # we got hostname from cico
            break
        fi
        echo "'cico node get' succeed, but can't get hostname from output"
    fi
    if [ $n -gt 5 ]; then
        # give up after 5 tries
        echo "giving up on 'cico node get'"
        exit 1
    fi
    echo "'cico node get' failed, trying again in 60s ($n/5)"
    n=$[$n+1]
    sleep 60
done
sshopts="-t -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -l root"
ssh_cmd="ssh $sshopts $CICO_hostname"

$ssh_cmd yum -y install rsync

if [ -n "${ghprbTargetBranch}" ]; then
    git rebase --preserve-merges origin/${ghprbTargetBranch}
else
    echo "Not a PR build, using master"
fi

rsync -e "ssh $sshopts" -Ha $(pwd)/ $CICO_hostname:payload \
&& /usr/bin/timeout 30m $ssh_cmd -t "cd payload && make test"
rtn_code=$?
if [ $rtn_code -eq 0 ]; then
    cico node done $CICO_ssid
else
    if [[ $rtn_code -eq 124 ]]; then
       echo "BUILD TIMEOUT";
       cico node done $CICO_ssid
    else
        # fail mode gives us 12 hrs to debug the machine
        curl "http://admin.ci.centos.org:8080/Node/fail?key=$CICO_API_KEY&ssid=$CICO_ssid"
    fi
fi
exit $rtn_code
