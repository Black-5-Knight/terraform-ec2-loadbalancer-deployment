

resource "aws_instance" "public_ec2"{
    count =length(var.public_subnet_id) 
    ami = var.ami_id
    instance_type = var.instance_type
    subnet_id = var.public_subnet_id[count.index]
    vpc_security_group_ids = [aws_security_group.public_security-group.id]
    key_name = aws_key_pair.kp.key_name #key pair attach
    associate_public_ip_address = "true"
    user_data =file("./modules/ec2-instance/public_user_data.sh")

    tags = {
        Name = "${var.Name}_public_ec2_${count.index + 1}",
        created-by="Yousef"
    }
    
}

resource "aws_instance" "private_ec2"{
    count = length(var.private_subnet_id)
    ami = var.ami_id
    instance_type = var.instance_type
    subnet_id = var.private_subnet_id[count.index]
    vpc_security_group_ids = [aws_security_group.private_security-group.id]
    key_name = aws_key_pair.kp.key_name #key pair attach
    associate_public_ip_address = "false"
    user_data =file("./modules/ec2-instance/private_user_data.sh")

    tags = {
        Name = "${var.Name}_private_ec2_${count.index + 1}",
        created-by="Yousef"
    }
    
}

resource "null_resource" "config_nginx" {
    count = length(var.public_subnet_id) 
    depends_on =[ local_file.make_config_file ] 
    provisioner "file" {
        source       ="./nginx_config.conf" # Local config file
        destination = "/tmp/nginx_config.conf" # Remote path on EC2

        # Connection details
        connection {
        type        = "ssh"
        user        = "ec2-user"
        private_key = tls_private_key.pk.private_key_pem
        host        = aws_instance.public_ec2[count.index].public_ip
        }
    }

    
    # Use remote-exec to apply the config
    provisioner "remote-exec" {
        inline = [
        "sudo yum install -y nginx"  , 
        "sudo cp /tmp/nginx_config.conf  /etc/nginx/conf.d/",
        "sudo systemctl restart nginx"
        ]

        # Connection details
        connection {
        type        = "ssh"
        user        = "ec2-user"
        private_key = tls_private_key.pk.private_key_pem
        host        = aws_instance.public_ec2[count.index].public_ip
        }
    }
}




resource "aws_security_group" "public_security-group" {
    name = "public-security-group"
    vpc_id = var.vpc_id

    ingress {
        from_port   = var.ssh_port
        to_port     = var.ssh_port
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }
    

    ingress {
        from_port   = var.HTTP_port
        to_port     = var.HTTP_port
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    egress {
        from_port   = 0
        to_port     = 0
        protocol    = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }
}
resource "aws_security_group" "private_security-group" {
    name = "private-security-group"
    vpc_id = var.vpc_id

    ingress {
        from_port   = var.ssh_port
        to_port     = var.ssh_port
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
        
    }
    ingress {
        from_port   = var.HTTP_port
        to_port     = var.HTTP_port
        protocol    = "tcp"
        cidr_blocks = [vpc_cidr_block] #we put vpc cider here to make it local only 
    }
    egress {
        from_port   = 0
        to_port     = 0
        protocol    = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }
}

# create private key for ssh connection 
resource "tls_private_key" "pk" {
  algorithm = "RSA"
  rsa_bits  = 4096
}
 # Create the key to AWS!!
resource "aws_key_pair" "kp" {
  key_name   = var.key_Name      
  public_key = tls_private_key.pk.public_key_openssh

}
# Save the private key to a file locally (will be destroyed with the key_pair resource)
resource "local_file" "private_key" {
  content  = tls_private_key.pk.private_key_pem
  filename = "${path.cwd}/${var.key_Name}.pem"
  provisioner "local-exec" {
    command = <<EOT
    chmod 400 ${path.cwd}/${var.key_Name}.pem
    EOT
  }
}

#print ips in file name all-ips
resource "null_resource" "write_ips_to_file" {
  provisioner "local-exec" {
    command = <<EOT
    echo "Public IPs:" > all-ips.txt
    for ip in ${join(" ", aws_instance.public_ec2.*.public_ip)}; do
      echo $ip >> all-ips.txt
    done
    
    echo "Private IPs:" >> all-ips.txt
    for ip in ${join(" ", aws_instance.private_ec2.*.private_ip)}; do
      echo $ip >> all-ips.txt
    done
    EOT
  }#join function used to make space sprate between ip then use in for loob to print it in file 


  depends_on = [aws_instance.public_ec2, aws_instance.private_ec2]
}

resource "local_file" "make_config_file" {
    content = <<EOT
server {
    listen 80;
    server_name _;  # any ip

    location / {
        proxy_pass http://${var.load_balancer_dns}:80;  # Your load balancer's DNS name
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
EOT
    filename = "./nginx_config.conf"  # Specify the path where you want to save the config
}


