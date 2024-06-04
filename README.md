# Local Kubernetes Testing and Playground

This repository is dedicated to providing a sandbox environment for testing local Kubernetes setups and related tools. It simplifies the process of installing Kind or K3S, setting up Ingress, Jenkins, and integrating other security/scanning tools. The setup is guided by a user-friendly prompt menu within the setup script.

Running
```bash
./setup.sh
```

Select installation option
```bash
    Setup Menu
    kc) Create Cluster KIND for CI
    ki) Create Cluster KIND
    kr) Remove Cluster KIND
    
    3c) Create Cluster K3S for CI
    3i) Create Cluster K3S
    3r) Remove Cluster K3S
    
    kd) Kyverno Policy Deployment
    td) Trivy Operator Deployment
    ts) Trivy Cluster Scan
    
    od) Operator Deployment
    
    0) Exit
```

## Components

### 1. Kind or K3S Installations

- **[Kind](https://kind.sigs.k8s.io/)**

- **[K3S](https://k3s.io/)**

### 2. [Contour Ingress Controller](https://projectcontour.io/)

### 3. Jenkins
A simple custom Jenkins using Dockerfile.
- Adding admin user
- Adding Kubernetes plugin
- Access it via http://localhost/jenkins (devozs / devozs)

### 4. Other Security/Scan Related Tools

### 4. [Kubebuilder](https://kubebuilder.io/) Operator Example

