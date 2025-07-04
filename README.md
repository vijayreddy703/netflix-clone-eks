# 🚀 Building and Deploying a Netflix Clone on AWS EKS with GitHub Actions CI/CD

In this project, I’ll walk you through how I built and deployed a full-stack **Netflix Clone** using modern DevOps best practices. The project integrates **GitHub Actions** for CI/CD, **SonarCloud** for code quality checks, **Trivy** for Docker image vulnerability scanning, **Docker Hub** for image storage, and **Terraform** for reusable AWS infrastructure — all deployed to a production-grade **AWS EKS cluster** with a managed node group.
---

## 🎬 Project Overview

The Netflix Clone is a React-based application that fetches and displays trending movies and shows using the TMDB API. It mimics Netflix’s modern UI with dynamic movie posters, trailers, and category rows.

### 🔧 Tech Stack:
- **Frontend**: React.js + Vite  
- **CI/CD**: GitHub Actions  
- **Security**: SonarCloud, Trivy  
- **Containerization**: Docker  
- **Registry**: Docker Hub  
- **Infrastructure**: Terraform (AWS EKS)

---

## 🗺️ Architecture Overview

![Netflix Clone Architecture Diagram](https://i.imgur.com/7kaeaDL.png)

## ✅ Code Quality with SonarCloud

Maintaining clean code is essential, especially in team environments. **SonarCloud** analyzes code for:
- Code smells
- Bugs
- Duplications
- Security vulnerabilities

By integrating it in the CI process, any issues are caught before merging.

```yaml
     code_quality_analysis:
    name: Code Quality Analysis
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0  
      - name: SonarQube Scan
        uses: SonarSource/sonarqube-scan-action@v5
        env:
          SONAR_TOKEN: ${{ secrets.SONAR_TOKEN }}
```

---

## 🔒 Docker Image built and image Security scan with Trivy

Before deploying any Docker image, I use **Trivy** to scan for:
- OS package vulnerabilities
- Language-specific dependency issues

This ensures no known CVEs are shipped into production.

```yaml
build_scan_docker_image:
    name: Build Docker Image and scan with Trivy
    runs-on: ubuntu-latest
    needs: code_quality_analysis
    steps:
      - uses: actions/checkout@v4
      - name: build docker image
        run: |
          docker build \
            --build-arg TMDB_V3_API_KEY="${{ secrets.TMDB_V3_API_KEY }}" \
            -t netflix:latest \
            -f ./Netflix-Clone/Dockerfile ./Netflix-Clone

      - name: Trivy Image Scan
        uses: aquasecurity/trivy-action@master
        continue-on-error: true
        with:
          image-ref: 'netflix:latest'
          format: 'table'
          output: 'trivy-image-results.txt'

      - name: Upload Trivy scan results
        uses: actions/upload-artifact@v4
        with:
          name: trivy-image-results
          path: trivy-image-results.txt

      - name: Save Docker image as tar
        run: docker save -o netflix-latest.tar netflix:latest

      - name: Upload Docker image artifact
        uses: actions/upload-artifact@v4
        with:
          name: netflix-latest
          path: netflix-latest.tar
```

---

## 📦 Download Docker Image Built & Push to Docker Hub

After passing quality and security checks, the image is built and tagged. The tagged image is pushed to Docker Hub

```yaml
push_docker_image:
    runs-on: ubuntu-latest
    needs: build_scan_docker_image
    steps:
      - name: Download Docker image artifact
        uses: actions/download-artifact@v4
        with:
          name: netflix-latest

      - name: Load Docker image
        run: docker load -i netflix-latest.tar
      - name: Push Docker Image to Docker Hub
        uses: docker/login-action@v2
        with:
          username: ${{ secrets.DOCKER_USERNAME }}
          password: ${{ secrets.DOCKER_PASSWORD }}

      - name: Push Docker Image
        run: |
          docker tag netflix:latest ${{ secrets.DOCKER_USERNAME }}/netflix-clone:latest
          docker push ${{ secrets.DOCKER_USERNAME }}/netflix-clone:latest
```

This makes the image globally accessible for Kubernetes to pull and run.

---

## ☁️ Infrastructure as Code with Terraform

To ensure reusability and automation, the infrastructure was built using **Terraform**. Key resources include:
- `aws_eks_cluster`
- `aws_eks_node_group`
- IAM roles and policies
- Networking components (VPC, subnets, security groups)

### Example: EKS Cluster and Managed Node Group

```hcl
resource "aws_eks_cluster" "eks_cluster" {
  name     = var.cluster_name
  role_arn = aws_iam_role.eks_cluster_role.arn

  vpc_config {
    subnet_ids              = module.networking.public_subnets
    security_group_ids      = [aws_security_group.eks_cluster_sg.id, aws_security_group.eks_worker_sg.id]
    endpoint_private_access = true
    endpoint_public_access  = true
  }


  enabled_cluster_log_types = ["api", "audit", "authenticator"]

  tags = var.tags
}

resource "aws_eks_node_group" "worker_node_group" {
  cluster_name    = var.cluster_name
  node_group_name = var.node_group_name
  node_role_arn   = aws_iam_role.eks_worker_node_role.arn
  subnet_ids      = module.networking.private_subnets

  scaling_config {
    desired_size = 1
    max_size     = 2
    min_size     = 1
  }
  instance_types = var.instance_types

  update_config {
    max_unavailable = 1
  }

  depends_on = [

    aws_iam_role_policy_attachment.AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.AmazonEC2ContainerRegistryReadOnly,
  ]

}
```

---

## ☸️ Deployment on AWS EKS

After provisioning the cluster with terraform, the application is deployed to eks using github actions cicd:

```yaml
deploy_to_eks:
    name: Deploy to EKS
    runs-on: ubuntu-latest
    needs: push_docker_image

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: ${{ secrets.AWS_REGION }} 

      - name: Install kubectl
        run: |
          curl -O https://s3.us-west-2.amazonaws.com/amazon-eks/1.33.0/2025-05-01/bin/linux/amd64/kubectl
          chmod +x kubectl
          sudo mv kubectl /usr/local/bin/

      - name: Update kubeconfig for EKS
        run: aws eks update-kubeconfig --region ${{ secrets.AWS_REGION }} --name ${{ secrets.EKS_CLUSTER_NAME }}

      - name: Deploy Kubernetes manifests
        run: |
          kubectl apply -f ./Netflix-Clone/k8-Manifest/deployment.yml
          kubectl apply -f ./Netflix-Clone/k8-Manifest/service.yml
      - name: Wait for deployment to be ready
        run: |
          kubectl rollout status deployment/netflix-app --timeout=300s || exit 1
          kubectl get pods
```

A Kubernetes manifest (`deployment.yaml`) is used:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: netflix-app
  labels:
    app: netflix-app
spec:
  replicas: 1
  selector:
    matchLabels:
      app: netflix-app
  template:
    metadata:
      labels:
        app: netflix-app
    spec:
      containers:
      - name: netflix-app
        image: ojosamuel/netflix-clone:latest
        ports:
        - containerPort: 80
  
```
An accompanying `Service.yml` and Ingress controller expose the app via a Load Balancer.
```yaml
apiVersion: v1
kind: Service
metadata:
  name: netflix-app
  labels:
    app: netflix-app
spec:
  type: LoadBalancer
  ports:
  - port: 80
    targetPort: 80
  selector:
    app: netflix-app
  
```
---
## 🧭 Step-by-Step Project Guide

### 1️⃣ Clone the GitHub Repository

```bash
git clone https://github.com/OjoOluwagbenga700/Netflix-Clone--aws-eks.git
cd Netflix-Clone--aws-eks
```

### 2️⃣ Configure GitHub Secrets

In your GitHub repository, navigate to **Settings > Secrets and variables > Actions > New repository secret** and add the following:

- `VITE_TMDB_API_KEY` — Your TMDB API key  
- `DOCKER_USERNAME` — Your Docker Hub username  
- `DOCKER_PASSWORD` — Your Docker Hub password or access token  
- `SONAR_TOKEN` — Token from SonarCloud account
- `AWS_ACCESS_KEY_ID` — Your AWS Access key ID
- `AWS_SECRET_ACCESS_KEY` — Your AWS Secret Access Key
- `AWS_REGION` — AWS Region of deployment
- `EKS_CLUSTER_NAME` — Your EKS Cluster Name


### 3️⃣ Deploy Infrastructure Using Terraform

Navigate to the Terraform directory in the project:

```bash
cd terraform
```
Initialize Terraform:

```bash
terraform init
```

Preview the resources to be created:

```bash
terraform plan
```
Apply the configuration to provision AWS resources:

```bash
terraform apply
```

> ⚠️ This creates your VPC, EKS cluster, managed node group, IAM roles, etc.

### 4️⃣ Push Your Code to Trigger GitHub Actions

Once infrastructure is ready and secrets are set, push your code. GitHub Actions automates the build, test, and deployment pipeline every time a new commit is pushed. 

```bash
git add .
git commit -m "Initial commit with CI/CD pipeline"
git push origin main
```
This triggers the GitHub Actions pipeline, which:

- Analyzes code with **SonarCloud**
- Builds Docker image with **VITE_TMDB_API_KEY**
- Scans it using **Trivy**
- Pushes it to **Docker Hub**
- Deploys it to **AWS EKS**
---

## 🔚 Conclusion

This Netflix Clone project showcases how you can integrate:
- 🚀 GitHub Actions for automated CI/CD  
- 🔍 SonarCloud for code quality  
- 🛡 Trivy for vulnerability scanning  
- 📦 Docker for containerization  
- ☁️ Terraform for infrastructure automation  
- ☸️ AWS EKS for scalable Kubernetes deployments

### 🔮 Next Steps:
- Add **ArgoCD** for GitOps-based deployments  
- Integrate **Prometheus + Grafana** for monitoring  
- Configure **Cert-Manager** for HTTPS

---
