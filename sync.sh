#!/bin/bash

[ -n "$DEBUG" ] && set -x
readonly CUR_DIR=$(cd $(dirname ${BASH_SOURCE:-$0}); pwd)

MY_REPO=zhangguanzhang
status_image_name=zhangguanzhang/gcr-data
interval=.
: ${max_process:=5} ${max_per:=70} ${push_time:=45}

# 

google_list=/tmp/docker/google.loop
hub_check_time=/tmp/docker/hub_check.time
hub_check_ns=/tmp/docker/hub_check.ns
hub_check_name=/tmp/docker/hub_check.name
sync_at=/tmp/docker/sync.at
    
[ -z "$start_time" ] && start_time=$(date +%s)
git_init(){
    git config --global user.name "zhangguanzhang"
    git config --global user.email zhangguanzhang@qq.com
    git remote rm origin
    git remote add origin git@github.com:zhangguanzhang/gcr.io.git
    git pull
    if git branch -a |grep 'origin/develop' &> /dev/null ;then
        git checkout develop
        git pull origin develop
        git branch --set-upstream-to=origin/develop develop
    else
        git checkout -b develop
        git pull origin develop
    fi
}
git_init

mkdir -p /tmp/docker
docker run -d --rm --name data $status_image_name sleep 10
while read file;do
    docker cp data:/root/$file /tmp/docker/
done < <(docker exec data ls /root/)
# 防止文件未同步到docker镜像里
[ -f "$google_list" ] && ls -1  gcr.io > google_list 

#--------------------------

Multi_process_init() {
    trap 'exec 5>&-;exec 5<&-;exit 0' 2
    pipe=`mktemp -u tmp.XXXX`
    mkfifo $pipe
    exec 5<>$pipe
    rm -f $pipe
    seq $1 >&5
}



git_commit(){
    local COMMIT_FILES_COUNT=$(git status -s|wc -l)
    local TODAY=$(date +%F)
    if [[ $(( (`date +%s` - start_time)/60 ))  -gt $push_time ]];then
        [ -z "$docker_time" ] && docker_time=`date +%s`
        if [[ $(( (`date +%s` - docker_time)/60 ))  -gt 2 ]];then
            mkdir docker
            cp -a /tmp/docker/* docker/
            cat>Dockerfile<<-EOF
                FROM zhangguanzhang/alpine
                COPY docker/* /root/
EOF
            docker build -t $status_image_name .
            docker push $status_image_name
            rm -rf docker Dockerfile
            docker_time=`date +%s`
        fi
        if [[ $COMMIT_FILES_COUNT -ne 0 ]];then
            git add -A
            git commit -m "Synchronizing completion at $TODAY"
            git push -u origin develop
        fi
    fi
}

add_yum_repo() {
cat > /etc/yum.repos.d/google-cloud-sdk.repo <<EOF
[google-cloud-sdk]
name=Google Cloud SDK
baseurl=https://packages.cloud.google.com/yum/repos/cloud-sdk-el7-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg
       https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
EOF
}

add_apt_source(){
export CLOUD_SDK_REPO="cloud-sdk-$(lsb_release -c -s)"
echo "deb http://packages.cloud.google.com/apt $CLOUD_SDK_REPO main" | sudo tee -a /etc/apt/sources.list.d/google-cloud-sdk.list
curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
}

install_sdk() {
    local OS_VERSION=$(grep -Po '(?<=^ID=")\w+' /etc/os-release)
    local OS_VERSION=${OS_VERSION:-ubuntu}
    if [[ $OS_VERSION =~ "centos" ]];then
        if ! [ -f /etc/yum.repos.d/google-cloud-sdk.repo ];then
            add_yum_repo
            yum -y install google-cloud-sdk
        else
            echo "gcloud is installed"
        fi
    elif [[ $OS_VERSION =~ "ubuntu" ]];then
        if ! [ -f /etc/apt/sources.list.d/google-cloud-sdk.list ];then
            add_apt_source
            sudo apt-get -y update && sudo apt-get -y install google-cloud-sdk
        else
             echo "gcloud is installed"
        fi
    fi
}

auth_sdk(){
    local AUTH_COUNT=$(gcloud auth list --format="get(account)"|wc -l)
    if [ $AUTH_COUNT -eq 0 ];then
        gcloud auth activate-service-account --key-file=$HOME/gcloud.config.json
    else
        echo "gcloud service account is exsits"
    fi
}

# gcloud(){
#     docker run --rm -v /tmp/gcloud:/root/.config/gcloud  gcr.io/google.com/cloudsdktool/cloud-sdk:latest gcloud "$@"
# }

# gcloud_auth(){
#     mkdir /tmp/gcloud
#     docker run --rm -v /tmp/gcloud:/root/.config/gcloud \
#       -v $HOME/gcloud.config.json:/root/gcloud.config.json \
#       gcr.io/google.com/cloudsdktool/cloud-sdk:latest gcloud auth activate-service-account --key-file=/root/gcloud.config.json ||
#         echo "gcloud service account is exsits"
# }


#  GCR_IMAGE_NAME  tag  REPO_IMAGE_NAME
image_tag(){
    docker pull $1:$2
    docker tag $1:$2 $3:$2
    docker rmi $1:$2
}


img_clean(){
    local domain=$1 namespace=$2 image_name=$3
    local Prefix=$domain$interval$namespace$interval
    shift 3
    while read img tag null;do
        docker push $img:$tag;docker rmi $img:$tag;
        [ "$tag" != latest ] && echo $domain/$namespace/$image_name:$tag > $domain/$namespace/$image_name/$tag ||
            $@ $domain/$namespace/$image_name > $domain/$namespace/$image_name/$tag
        git_commit
    done < <(docker images --format {{.Repository}}' '{{.Tag}}' '{{.Size}} | awk -vcut=$MY_REPO/$Prefix '$0~cut{print $0 | "sort -hk3" }')
    git_commit
}


# example: gcr.io/$ns  return gcr.io/$ns/$img_name
google::name(){
    gcloud container images list --format="value(NAME)" --repository=$@
}
# example: gcr.io/$ns/$img_name return $tag
google::tag(){
    gcloud container images list-tags  --format="get(TAGS)" --filter='tags:*' $@  | sed 's#;#\n#g'
}
# example: gcr.io/$ns/$img_name return $sha256
google::latest_digest(){
    gcloud container images list-tags --format='get(DIGEST)' --filter="tags=latest" $@ 
}


# google::name(){
#     https://console.cloud.google.com/gcr/images/google-containers/GLOBAL
#     curl -XPOST -ks 'https://console.cloud.google.com/m/gcr/entities/list' \
#            -H 'User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/68.0.3440.7 Safari/537.36' \
#            -H 'Content-Type: application/json;charset=UTF-8' \
#            -H 'Accept: application/json, text/plain, */*' \
#            --data-binary ['"'"${@#*/}"'"']   |
#         awk -vio=$@ -F'"' '/"/{if(NR==3){if(!a[$4]++)print io"/"$4}else{if(!a[$2]++)print io"/"$2}}'
# }
# google::tag(){
#     read null ns name< <(tr '/' ' '<<<$@)
#     curl -ks -XGET https://gcr.io/v2/${ns}/${name}/tags/list | jq -r .tags[]
# }
# google::latest_digest(){
#     read null ns name< <(tr '/' ' '<<<$@)
#     curl -ks -XGET https://gcr.io/v2/${ns}/${name}/tags/list | jq -r '.manifest | with_entries(select(.value.tag[] == "latest"))|keys[]'
# }

#quay::name(){
#    NS=${1#*/}
#    curl -sL 'https://quay.io/api/v1/repository?public=true&namespace='${NS} | jq -r '"quay.io/'${NS}'/"'" + .repositories[].name"
#}
#quay::tag(){
#    curl -sL "https://quay.io/api/v1/repository/${@#*/}?tag=info"  | jq -r .tags[].name
#}
#quay::latest_digest(){
# #    curl -sL "https://quay.io/api/v1/repository/prometheus/alertmanager/tag" | jq -r '.tags[]|select(.name == "latest" and (.|length) == 5 ).manifest_digest'
#   curl -sL "https://quay.io/api/v1/repository/${@#*/}?tag=info" | jq -r '.tags[]|select(.name == "latest" and (has("end_ts")|not) ).manifest_digest'
#}


image_pull(){
    REPOSITORY=$1
    echo 'Sync the '$REPOSITORY
    shift
    domain=${REPOSITORY%%/*}
    namespace=${REPOSITORY##*/}
    Prefix=$domain$interval$namespace$interval
    # REPOSITORY is the name of the dir,convert the '/' to '.',and cut the last '.'
    [ ! -d "$domain/$namespace" ] && mkdir -p $domain/$namespace
    # gcr.io/$ns/$img_name
    while read SYNC_IMAGE_NAME;do
        image_name=${SYNC_IMAGE_NAME##*/}
        MY_REPO_IMAGE_NAME=${Prefix}${image_name}
        [ ! -d "$domain/$namespace/$image_name" ] && mkdir -p "$domain/$namespace/$image_name"
        [ -f "$domain/$namespace/$image_name"/latest ] && mv $domain/$namespace/$image_name/latest{,.old}
        while read tag;do
        #处理latest标签
            [[ "$tag" == latest && -f "$domain/$namespace/$image_name"/latest.old ]] && {
                $@::latest_digest $SYNC_IMAGE_NAME > $domain/$namespace/$image_name/latest
                diff $domain/$namespace/$image_name/latest{,.old} &>/dev/null &&
                    { rm -f $domain/$namespace/$image_name/latest.old;continue; } ||
                      rm $domain/$namespace/$image_name/latest{,.old}
            }
            [ -f "$domain/$namespace/$image_name/$tag" ] && { trvis_live;continue; }
            [[ $(df -h| awk  '$NF=="/"{print +$5}') -ge "$max_per" || -n $(sync_commit_check) ]] && { wait;img_clean $domain $namespace $image_name $@::latest_digest; }

                read -u5
                {
                    [ -n "$tag" ] && image_tag $SYNC_IMAGE_NAME $tag $MY_REPO/$MY_REPO_IMAGE_NAME
                    echo >&5
                }&

        done < <($@::tag $SYNC_IMAGE_NAME)
        wait
        img_clean $domain $namespace $image_name $@::latest_digest
    done < <($@::name $REPOSITORY)
}

sync_commit_check(){
    [[ $(( (`date +%s` - start_time)/60 )) -gt $push_time || -n "$(docker images | awk '$NF~"GB"')" ]] &&
        echo ture || false
}

# img_name tag
hub_tag_exist(){
    curl -s https://hub.docker.com/v2/repositories/${MY_REPO}/$1/tags/$2/ | jq -r .name
}


trvis_live(){
    [ $(( (`date +%s` - live_start_time)/60 )) -ge 8 ] && { live_start_time=$(date +%s);echo 'for live in the travis!'; }
}

sync_domain_repo(){
    path=${1%/}
    local name tag
    while read name tag;do
        [ "$(( (`date +%s` - start_time)/60 ))"  -gt "$push_time" ] && break
        img_name=$( sed 's#/#'"$interval"'#g'<<<$name )
        trvis_live       
        read -u5
        {
            [ "$( hub_tag_exist $img_name $tag )" == null ] && rm -f $name/$tag
            echo >&5
        }&
    done < <( find $path/ -type f | sed 's#/# #3' )
    wait
    git_commit
}



main(){

    Multi_process_init $(( max_process * 4 ))
    live_start_time=$(date +%s)
    read sync_time < $hub_check_time #每隔 12个小时以dockerhub为准，清楚本地多余的文件

    [ $(( (`date +%s` - sync_time)/3600 )) -ge 12 ] && {
        [ ! -f "$hub_check_ns" ] && ls gcr.io > "$hub_check_ns"
        hub_ns_break_count=`wc -l $hub_check_time | cut -d " " -f1`
        i=0
        while read ns;do
            [ "$i" -eq "$hub_ns_break_count" ] && break #防止循环,----之间才是loop核心
            #-------------
            [ ! -f "$hub_check_name" ] && ls gcr.io/$ns > $hub_check_name
            hub_name_break_count=`wc -l $hub_check_time | cut -d " " -f1`
            j=0
            while read name;do
                [ "$j" -eq "$hub_name_break_count" ] && break #防止循环,----之间才是loop核心
                #-------------
                sync_domain_repo gcr.io/$ns/$name
                #-------------
                sed -i 1d "$hub_check_name"
                let j++
            done < "$hub_check_name"
            rm -f "$hub_check_name"
            #-------------
            sed -i 1d "$hub_check_ns"
            let i++
        done < "$hub_check_ns"
        rm -f "$hub_check_ns"
        echo the sync has done! 
        date +%s > $hub_check_time
    }
    exec 5>&-;exec 5<&-
    #开始同步gcr

    install_sdk
    auth_sdk
    Multi_process_init $max_process

    list_loop_break_count=`wc -l $google_list | cut -d " " -f1`
    i=0
    while read repo;do
        [ "$i" -ge "$list_loop_break_count" ] && break
        image_pull gcr.io/$repo google
        sed -i 1d "$google_list"
        echo $repo >> "$google_list"
        let i++
    done < "$google_list"

    exec 5>&-;exec 5<&-
    
    COMMIT_FILES_COUNT=$(git status -s|wc -l)
    TODAY=$(date +%F)
    mkdir docker
    cp -a /tmp/docker/* docker/
    cat>Dockerfile<<-EOF
        FROM zhangguanzhang/alpine
        COPY docker/* /root/
EOF
    docker build -t $status_image_name .
    docker push $status_image_name
    rm -rf docker Dockerfile
    if [ $COMMIT_FILES_COUNT -ne 0 ];then
        git add -A
        git commit -m "Synchronizing completion at $TODAY"
        git push -u origin develop
    fi
}

main
