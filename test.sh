#!/bin/bash

set -x 
set -e 
max_process=$1
MY_REPO=zhangguanzhang
interval=.
max_per=70

export start_time=$(date +%s)

Multi_process_init() {
    trap 'exec 5>&-;exec 5<&-;exit 0' 2
    pipe=`mktemp -u tmp.XXXX`
    mkfifo $pipe
    exec 5<>$pipe
    rm -f $pipe
    seq $1 >&5
}


hub_tag_exist(){
    curl -s https://hub.docker.com/v2/repositories/${MY_REPO}/$1/tags/$2/ | jq -r .name
}


trvis_live(){
    [ $(( (`date +%s` - live_start_time)/60 )) -ge 8 ] && { live_start_time=$(date +%s);echo 'for live in the travis!'; } || :
}
sync_domain_repo(){
    path=$1
    while read name tag;do
        img_name=$( sed 's#/#'"$interval"'#g'<<<$name )
        trvis_live
        read -u5
        {
            [ "$( hub_tag_exist $img_name $tag )" == null ] && rm -f $name/$tag || :
            echo >&5
        }&
    done < <( find $path/ -type f | sed 's#/# #3' )
    wait
}

Multi_process_init 40
sync_domain_repo gcr.io/istio-release/mixer_debug
echo end
