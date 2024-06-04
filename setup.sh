#!/bin/bash

green='\e[32m'
blue='\e[34m'
red="\[\033[0;31m\]"
clear='\e[0m'

ColorGreen(){
	echo -ne "$green$1$clear"
}
ColorBlue(){
	echo -ne "$blue$1$clear"
}
ColorRed(){
	echo -ne "$red$1$clear"
}

export KUBECONFIG=~/.kube/config
CLUSTER_NAME="test"
CLUSTER_KIND="kind-${CLUSTER_NAME}"
JENKINS_NS=devops-jenkins
CLUSTER_TYPE=K3S #KIND or K3S

menu(){
echo -ne "
Setup Menu
$(ColorGreen 'kc)') Create Cluster KIND for CI
$(ColorGreen 'ki)') Create Cluster KIND
$(ColorGreen 'kr)') Remove Cluster KIND

$(ColorGreen '3c)') Create Cluster K3S for CI
$(ColorGreen '3i)') Create Cluster K3S
$(ColorGreen '3r)') Remove Cluster K3S

$(ColorGreen 'kd)') Kyverno Policy Deployment
$(ColorGreen 'td)') Trivy Operator Deployment
$(ColorGreen 'ts)') Trivy Cluster Scan
$(ColorGreen 'cp)') Crossplane Deployment

$(ColorGreen 'od)') Operator Deployment

$(ColorGreen '0)') Exit
$(ColorBlue 'Choose an option:') "
        read -r a
        case $a in
	        kc) deploy_ci_kind ; exit ;;
	        ki) create_cluster_kind ; exit ;;
	        kr) remove_cluster_kind ; menu ;;

	        3c) deploy_ci_k3s ; exit ;;
	        3i) create_cluster_k3s ; exit ;;
	        3r) remove_cluster_k3s ; menu ;;


	        kd) kyverno_install ; exit ;;
	        td) trivy_install ; exit ;;
	        ts) trivy_scan ; exit ;;
	        cp) install_crossplane ; exit ;;

	        od) create_deploy_operator ; exit ;;


			0) exit 0 ;;
			*) echo -e "${red}Wrong option.${clear}"; menu;;
        esac
}

create_cluster_kind(){
    command -v kind >/dev/null 2>&1 || { echo >&2 "I require kind but it's not installed.  Aborting."; exit 1; }
    echo -ne "$(ColorBlue "Creating new Kind cluster with name ${CLUSTER_NAME} (delete if already exists)")"
    echo -ne "\n"
    CLUSTER_TYPE=KIND
    sudo kind delete cluster -n ${CLUSTER_NAME}
#    sudo kind create cluster -n ${CLUSTER_NAME}

cat <<EOF | kind create cluster -n ${CLUSTER_NAME} --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
networking:
  apiServerAddress: "0.0.0.0"
  apiServerPort: 58350
nodes:
- role: control-plane
  kubeadmConfigPatches:
  - |
    kind: InitConfiguration
    nodeRegistration:
      kubeletExtraArgs:
        node-labels: "ingress-ready=true"
  extraPortMappings:
  - containerPort: 80
    hostPort: 80
    protocol: TCP
  - containerPort: 443
    hostPort: 443
    protocol: TCP
EOF

#    kubectl cluster-info --context ${CLUSTER_KIND}
    kind export kubeconfig -n ${CLUSTER_NAME}
    kubectl cluster-info --context kind-test
    post_install_print
}

remove_cluster_kind(){
  echo -ne "$(ColorBlue "Deleting existing cluster with name ${CLUSTER_NAME}")"
  sudo kind delete cluster -n ${CLUSTER_NAME}
}

create_cluster_k3s(){
    remove_cluster_k3s
    echo -ne "$(ColorBlue "Creating new k3s cluster with name ${CLUSTER_NAME} (delete if already exists)")"
    echo -ne "\n"
    CLUSTER_TYPE=K3S
    curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server --disable traefik" sh
#    curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server" sh -s - --disable-traefik
#    curl -sfL https://get.k3s.io | sh -
    sudo chmod 644 /etc/rancher/k3s/k3s.yaml
    export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
    post_install_print
}

remove_cluster_k3s(){
  echo -ne "$(ColorBlue "Deleting existing cluster with name ${CLUSTER_NAME}")"
  /usr/local/bin/k3s-uninstall.sh
}

create_cluster_openshift(){
    echo -ne "$(ColorBlue "Creating new OpenShift cluster with name ${CLUSTER_NAME} (delete if already exists)")"

}

deploy_ci_kind(){
  create_cluster_kind
  install_contour
  install_jenkins
  postgres_install
  install_prometheus
  build_deploy_metmon
  kasten_install
  create_ingress
  post_install_print
}

deploy_ci_k3s(){
  create_cluster_k3s
  install_contour
  install_jenkins
  postgres_install
  install_prometheus
  build_deploy_metmon
  kasten_install
  create_ingress
  post_install_print
}

install_contour(){
    kubectl apply -f https://projectcontour.io/quickstart/contour.yaml
    kubectl rollout status -n projectcontour deployment contour
    kubectl patch daemonsets -n projectcontour envoy -p '{"spec":{"template":{"spec":{"nodeSelector":{"ingress-ready":"true"},"tolerations":[{"key":"node-role.kubernetes.io/control-plane","operator":"Equal","effect":"NoSchedule"},{"key":"node-role.kubernetes.io/master","operator":"Equal","effect":"NoSchedule"}]}}}}'
}

install_crossplane(){
  command -v helm >/dev/null 2>&1 || { echo >&2 "I require helm but it's not installed.  Aborting."; exit 1; }
  helm repo add crossplane-stable https://charts.crossplane.io/stable
  helm repo update
  helm install crossplane \
  --namespace crossplane-system \
  --create-namespace crossplane-stable/crossplane


}

install_jenkins(){
  . ./scan/kics.sh "./jenkins"
  docker build -t myjenkins:2.440.1-1 ./jenkins

  if [ "${CLUSTER_TYPE}" == "KIND" ]; then
    kind load docker-image myjenkins:2.440.1-1 -n ${CLUSTER_NAME}
  elif [ "${CLUSTER_TYPE}" == "K3S" ]; then
      export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
      docker save --output myjenkins-v2.440.1-1.tar myjenkins:2.440.1-1
      sudo k3s ctr images import myjenkins-v2.440.1-1.tar
  fi

  DEFAULT_NODE=$(kubectl get node | awk 'NR==2 {print $1}')
  sed "s/DEFAULT_NODE/${DEFAULT_NODE}/g" ./jenkins/kubernetes/volume_template.yaml > ./jenkins/kubernetes/volume.yaml
  kubectl apply -k ./jenkins/kubernetes
  kubectl rollout status -n devops-jenkins deployment jenkins

#  JENKINS_POD=$(kubectl get pod -n ${JENKINS_NS} | awk 'NR==2 {print $1}')
#  JENKINS_TEMP_PASSWORD=$(kubectl exec -it -n ${JENKINS_NS} "${JENKINS_POD}" -- cat /var/jenkins_home/secrets/initialAdminPassword)
#  echo -e "Jenkins Default Admin Password: ${JENKINS_TEMP_PASSWORD}"
}

create_ingress(){
  kubectl apply -k ./ingress
}

kyverno_install(){
#  command -v kyverno >/dev/null 2>&1 || { echo >&2 "I require kyverno but it's not installed.  Aborting."; exit 1; }
  kubectl create -f https://github.com/kyverno/kyverno/releases/download/v1.11.1/install.yaml
  kubectl apply -f kyverno/policies/enforce-attestation.yaml
}

trivy_install(){
  command -v helm >/dev/null 2>&1 || { echo >&2 "I require helm but it's not installed.  Aborting."; exit 1; }
  helm version
  helm repo add aqua https://aquasecurity.github.io/helm-charts/
  helm repo update
  helm install trivy-operator aqua/trivy-operator \
     --namespace trivy-system \
     --create-namespace \
     --version 0.21.0
}

trivy_scan(){
  command -v trivy >/dev/null 2>&1 || { echo >&2 "I require trivy but it's not installed.  Aborting."; exit 1; }
  trivy version
  trivy k8s --report=summary cluster
}

create_deploy_operator(){
  (cd setup-operator &&
  command -v make >/dev/null 2>&1 || { echo >&2 "I require make but it's not installed.  Aborting."; exit 1; }
#  make docker-build docker-push IMG=setup-operator:0.0.1
  make docker-build IMG=setup-operator:0.0.1

  command -v kind >/dev/null 2>&1 || { echo >&2 "I require kind but it's not installed.  Aborting."; exit 1; }
  kind load docker-image setup-operator:0.0.1 -n ${CLUSTER_NAME}

  command -v k3s >/dev/null 2>&1 || { echo >&2 "I require k3s but it's not installed.  Aborting."; exit 1; }
  docker save --output setup-operator:0.0.1.tar setup-operator:0.0.1
  sudo k3s ctr images import setup-operator:0.0.1.tar

  make deploy IMG=setup-operator:0.0.1
  sleep 10
  # check for custom annotation
  JENKINS_POD=$(kubectl get pod -n ${JENKINS_NS} | awk 'NR==2 {print $1}')
  echo "Printing Jenkins POD ${JENKINS_POD} Annotations:"
  kubectl describe pod -n devops-jenkins "${JENKINS_POD}" | grep Annotations
  )

}

install_prometheus(){
  command -v helm >/dev/null 2>&1 || { echo >&2 "I require helm but it's not installed.  Aborting."; exit 1; }
  helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
  helm repo update
  kubectl apply -k ./monitoring/kubernetes
  helm upgrade --install -n monitoring prometheus prometheus-community/kube-prometheus-stack -f monitoring/values.yaml
}

build_deploy_metmon(){
  kubectl create namespace metmon
  (cd metmon && ./mvnw spring-boot:build-image -Dspring-boot.build-image.imageName=metmon:0.0.1)
  kind load docker-image metmon:0.0.1 -n ${CLUSTER_NAME}
  kubectl apply -k ./metmon/kubernetes
}

kasten_install(){
  helm repo add kasten https://charts.kasten.io/
  kubectl create namespace kasten-io
  helm upgrade --install k10 kasten/k10 --namespace=kasten-io \
  --set auth.tokenAuth.enabled=true \
  --set prometheus.server.baseURL="/k10/prometheus/" \
  --set prometheus.server.prefixURL="/k10/prometheus/" \
  --set grafana.prometheusPrefixURL="/k10/prometheus/"
  kubectl apply -f ./kasten/kubernetes/kasten-admin-credentials.yaml

  echo -e "http://localhost/k10/#/dashboard"
  echo -e "Kasten Access Token"
  kubectl get secret kasten-admin-credentials --namespace kasten-io -ojsonpath="{.data.token}" | base64 --decode
  echo -e "\n"
}

postgres_install(){
  helm repo add cnpg https://cloudnative-pg.github.io/charts
  helm upgrade --install cnpg cnpg/cloudnative-pg --namespace cnpg-system --create-namespace --wait
  kubectl apply -k ./postgres/kubernetes
}

post_install_print(){
    echo "Cluster installation done with type ${CLUSTER_TYPE}"
    if [ "${CLUSTER_TYPE}" == "KIND" ]; then
      echo "Set K8S context by running: export KUBECONFIG=~/.kube/config"
    elif [ "${CLUSTER_TYPE}" == "K3S" ]; then
      echo "Set K8S context by running: export KUBECONFIG=/etc/rancher/k3s/k3s.yaml"
    fi
}

menu