resource "aws_instance" "kubectl-server" {
  ami                         = "ami-04a81a99f5ec58529"
  key_name                    = "ub_key"
  instance_type               = "t2.micro"
  associate_public_ip_address = true
  subnet_id                   = aws_subnet.public-1.id
  vpc_security_group_ids      = [aws_security_group.allow_tls.id]

  tags = {
    Name = "master_node"
  }

  user_data = <<-EOF
    #!/bin/bash
    # Update the package list and install dependencies
    sudo apt-get update -y
    sudo apt-get install -y curl unzip apt-transport-https

    # Install kubectl
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl.sha256"
    echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check
    sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

    # Install AWS CLI
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip awscliv2.zip
    sudo ./aws/install

    # Configure AWS CLI
    aws configure set aws_access_key_id AKIA2UC3FJGRFK2EMUXH
    aws configure set aws_secret_access_key 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
    aws configure set region us-east-1

    # Update kubeconfig for EKS
    aws eks update-kubeconfig --region us-east-1 --name devendra-eks

    # Create a directory and deploy NGINX
    mkdir -p /home/ubuntu/nginx

    cat <<EOL > /home/ubuntu/nginx/nginx.yaml
    apiVersion: apps/v1
    kind: Deployment
    metadata:
      name: nginx-deployment
    spec:
      replicas: 2
      selector:
        matchLabels:
          app: nginx
      template:
        metadata:
          labels:
            app: nginx
        spec:
          containers:
          - name: nginx
            image: nginx:1.14.2
            ports:
            - containerPort: 80
    EOL

    kubectl apply -f /home/ubuntu/nginx/nginx.yaml

    cat <<EOL > /home/ubuntu/nginx/nginx_service.yaml
    apiVersion: v1
    kind: Service
    metadata:
      name: nginx-service
    spec:
      selector:
        app: nginx
      ports:
        - protocol: TCP
          port: 80
          targetPort: 80
      type: LoadBalancer
    EOL

    kubectl apply -f /home/ubuntu/nginx/nginx_service.yaml
  EOF
}


resource "aws_eks_node_group" "node-grp" {
  cluster_name    = aws_eks_cluster.eks.name
  node_group_name = "node-group_devendra"
  node_role_arn   = aws_iam_role.worker.arn
  subnet_ids      = [aws_subnet.public-1.id, aws_subnet.public-2.id]
  capacity_type   = "ON_DEMAND"
  disk_size       = "20"
  instance_types  = ["t2.medium"]

  remote_access {
    ec2_ssh_key               = "ub_key"
    source_security_group_ids = [aws_security_group.allow_tls.id]
  }

  labels = tomap({ env = "dev" })

  scaling_config {
    desired_size = 2
    max_size     = 3
    min_size     = 1
  }

  update_config {
    max_unavailable = 1
  }

  depends_on = [
    aws_iam_role_policy_attachment.AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.AmazonEC2ContainerRegistryReadOnly,
    #aws_subnet.pub_sub1,
    #aws_subnet.pub_sub2,
  ]
}
