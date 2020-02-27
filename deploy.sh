# !/bin/bash

# MacOS
# Install Virtual Box from https://www.virtualbox.org/wiki/Downloads
# Install kubectl: brew install kubectl
# Install minikube: brew install minikube

# For Ubuntu
# Install libvirt and qemu-kvm on your system, e.g.
# Debian/Ubuntu (for older Debian/Ubuntu versions, you may have to use libvirt-bin instead of libvirt-clients and libvirt-daemon-system)
sudo apt install libvirt-clients libvirt-daemon-system qemu-kvm

# Add yourself to the libvirt group so you don't need to sudo
# NOTE: For older Debian/Ubuntu versions change the group to `libvirtd`
sudo usermod -a -G libvirt $(whoami)

# Update your current session for the group change to take effect
# NOTE: For older Debian/Ubuntu versions change the group to `libvirtd`
newgrp libvirt

# Install the driver
curl -Lo docker-machine-driver-kvm2 https://storage.googleapis.com/minikube/releases/latest/docker-machine-driver-kvm2 \
&& chmod +x docker-machine-driver-kvm2 \
&& sudo cp docker-machine-driver-kvm2 /usr/local/bin/ \
&& rm docker-machine-driver-kvm2

# Install kubectl
sudo apt-get update && sudo apt-get install -y apt-transport-https
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
sudo touch /etc/apt/sources.list.d/kubernetes.list
echo "deb http://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee -a /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update
sudo apt-get install -y kubectl

kubectl version

# Get minikube
curl -Lo minikube https://storage.googleapis.com/minikube/releases/v0.28.0/minikube-linux-amd64
chmod +x minikube
sudo mv minikube /usr/local/bin/


# Start Kubernetes cluster
# Kubeflow 0.7.1 Kubernetes 1.15.0
minikube start --cpus 4 --memory 8096 --disk-size=40g --kubernetes-version 1.15.0

# The following command is optional. It adds the kfctl binary to your path.
# If you don't add kfctl to your path, you must use the full path
# each time you run kfctl.
# Use only alphanumeric characters or - in the directory name.
export PATH=$PATH:$HOME/kubeflow/

# Set KF_NAME to the name of your Kubeflow deployment. You also use this
# value as directory name when creating your configuration directory.
# For example, your deployment name can be 'my-kubeflow' or 'kf-test'.
export KF_NAME='kf-poc'

# Set the path to the base directory where you want to store one or more
# Kubeflow deployments. For example, /opt/.
# Then set the Kubeflow application directory for this deployment.
export BASE_DIR=$HOME/kubeflow
export KF_DIR=${BASE_DIR}/kf-poc

# Set the configuration file to use when deploying Kubeflow.
# The following configuration installs Istio by default. Comment out
# the Istio components in the config file to skip Istio installation.
# See https://github.com/kubeflow/kubeflow/pull/3663
export CONFIG_URI="https://raw.githubusercontent.com/kubeflow/manifests/v0.7-branch/kfdef/kfctl_k8s_istio.0.7.1.yaml"

wget https://github.com/kubeflow/manifests/archive/v0.7-branch.tar.gz ${KF_DIR}
wget ${CONFIG_URI} ${KF_DIR}
tar xvf v0.7-branch.tar.gz
rm -rf ./.cache ./kustomize
# Change uri field in .yaml file to point to the downloaded manifest directory.
#    `uri: file:/path-to-file/manifests-0.7-branch`
kfctl apply -V -f ${KF_DIR}/kfctl_k8s_istio.0.7.1.yaml

# Once kubeflow is deployed we need to expose the UI using Istio
# curl -L https://istio.io/downloadIstio | sh -
# cd istio-X.X.X
# export PATH=$PWD/bin:$PATH

# In the Istio folder start httpbin in order to start configuring an Ingress
# Gateway to expose Kubeflow UI
kubectl apply -f samples/httpbin/httpbin.yaml
# Kubeflow exposes the UI using NodePort instead of LoadBalancer. You can know
# this by looking at external Ip, if set is LoadBalancer, else is NodePort
kubectl get svc istio-ingressgateway -n istio-system
# Set ingress ports
export INGRESS_PORT=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.spec.ports[?(@.name=="http2")].nodePort}')
export SECURE_INGRESS_PORT=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.spec.ports[?(@.name=="https")].nodePort}')
# Set the ingress IP. As we are using minikube
export INGRESS_HOST=$(minikube ip)
# Create an Istio gateway
kubectl apply -f - <<EOF
apiVersion: networking.istio.io/v1alpha3
kind: Gateway
metadata:
  name: httpbin-gateway
spec:
  selector:
    istio: ingressgateway # use Istio default gateway implementation
  servers:
  - port:
      number: 80
      name: http
      protocol: HTTP
    hosts:
    - "httpbin.example.com"
EOF
# Configure routes for traffic
kubectl apply -f - <<EOF
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  name: httpbin
spec:
  hosts:
  - "httpbin.example.com"
  gateways:
  - httpbin-gateway
  http:
  - match:
    - uri:
        prefix: /status
    - uri:
        prefix: /delay
    route:
    - destination:
        port:
          number: 8000
        host: httpbin
EOF
# Finally access ingress service using the browser
kubectl apply -f - <<EOF
apiVersion: networking.istio.io/v1alpha3
kind: Gateway
metadata:
  name: httpbin-gateway
spec:
  selector:
    istio: ingressgateway # use Istio default gateway implementation
  servers:
  - port:
      number: 80
      name: http
      protocol: HTTP
    hosts:
    - "*"
---
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  name: httpbin
spec:
  hosts:
  - "*"
  gateways:
  - httpbin-gateway
  http:
  - match:
    - uri:
        prefix: /headers
    route:
    - destination:
        port:
          number: 8000
        host: httpbin
EOF
# Yay! It works. Now you can access the Kubeflow UI using $INGRESS_HOST:$INGRESS_PORT

# Now, lets deploy Pachyderm inside our Kubeflow cluster
# First lets check the kubeflow namespace
kubectl get pods --all-namespaces
# In this case, the name is Kubeflow
# Install Pachyderm
brew tap pachyderm/tap && brew install pachyderm/tap/pachctl@1.9
# Deploy Pachyderm into the kubeflow cluster
pachctl deploy local --namespace kubeflow
# Wait for Pachyderm to deploy in Kubeflow. It takes around 8 min
kubectl get pods --namespace kubeflow
# Once deployed do port-forwarding
pachctl port-forward

# Finish! We can start using Pachyderm inside Kubeflow... pachctl create repo raw_data
