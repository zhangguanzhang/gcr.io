# use the travis to sync the docker images of the gcr.io and quay.io 

[![Build Status](https://travis-ci.org/zhangguanzhang/gcr.io.svg?branch=develop)](https://travis-ci.org/zhangguanzhang/gcr.io)

## 更新
 * 2018/07/15 - 优先推送GB镜像,防止有些全部GB的镜像占满空间
 * 2018/07/18 - 重写逻辑,实现伪接口方便后续扩展
 * 2018/07/19 - quay查询tag有问题,修复
 * 2018/07/22 - 部分文件生成但是未推送镜像到dockerhub,增加文件check来解决
 * 2018/07/23 - 文件check增加时间间隔触发,设置为6小时
 * 2018/07/26 - 增加loop文件,实现每次travis超时后下次还能从上次的namespace继续同步实现loop
 * 2018/07/29 - travis 10分钟不输出会中断,文件check不输出会超时,增加live输出达到存活
 * 2018/08/20 - 文件太多,分为两个仓库同步
 * 2018/09/22 - gcloud-sdk报错,改成http接口查询各项信息
GOOLE_NAMESPACE:
```
google_containers kubernetes-helm runconduit google-samples k8s-minikube heptio-images tf-on-k8s-dogfood spinnaker-marketplace istio-release kubernetes-e2e-test-images cloud-datalab linkerd-io distroless
```
QUAY_NAMESPACE:
```
coreos wire calico prometheus outline weaveworks hellofresh kubernetes-ingress-controller replicated kubernetes-service-catalog 3scale
```
同步以上镜像,另外
k8s.gcr.io <==> gcr.io/google-containers <==> gcr.io/google_containers 


## How to use?

### 拉取
假设需要拉取gcr.io/google_containers/pause:3.0
```
$ curl -s https://www.zhangguanzhang.com/pull | bash -s -- gcr.io/google_containers/pause:3.0
```
### 查询
#### 查询域名仓库下的namespace和namespace里的镜像列表
```
$ curl -s https://www.zhangguanzhang.com/pull | bash -s search gcr.io
google-samples
google_containers
k8s-minikube
kubernetes-helm
runconduit
spinnaker-marketplace
tf-on-k8s-dogfood
$ curl -s https://www.zhangguanzhang.com/pull | bash -s search gcr.io/google_containers
addon-builder
addon-resizer-amd64
addon-resizer-arm
addon-resizer-arm64
addon-resizer-ppc64le
addon-resizer-s390x
......
```

#### 查询镜像的所有tag或者是否存在tag时
```
$ curl -s https://www.zhangguanzhang.com/pull | bash -s -- search gcr.io/google_containers/kube-apiserver-amd64
v1.10.0-alpha.0
v1.10.0-alpha.1
v1.10.0-alpha.2
v1.10.0-alpha.3
v1.10.0-beta.0
......
$ curl -s https://www.zhangguanzhang.com/pull | bash -s -- search gcr.io/google_containers/kube-apiserver-amd64:v1.9.3
v1.9.3
```

或者自己把内容保存为脚本拉取


## 过程:
### [click me to see](https://zhangguanzhang.github.io/2018/07/08/travis-sync-gcr-io/)
方便后期扩展
利用shell的先展开变量这一特点来实现了伪接口扩展来拉取其他仓库
```bash
foo(){
    while read img;do
        while read tag;do
            echo docker pull $img:$tag
            echo docker push repo/$img:$tag
        done < <( $@::get_img_tags $img)
    done < <( $@::get_names )
}


google::get_names(){

}

google::get_img_tags(){

}

quay_io::get_names(){

}
quay_io::get_img_tags(){

}


foo google
foo quay_io
```

