# We start things off by calling the CloudFormation function.
CloudFormation {
  # Declare the template format version.
  AWSTemplateFormatVersion "2010-09-09"

  Description "Babysteps example consisting of 2 EC2 instances behind an ELB"

  # A standard ruby variable we can use for identification later on
  templateName = "Babysteps"

  # We define here how many EC2 instances we want to have available
  numberOfInstances = 2

  ##### Parameters section #####

  # Define the instance type of our new servers
  Parameter("InstanceType") {
    Description "Type of EC2 instance to launch"
    Type "String"
    Default "t2.micro"
  }

  # When setting up an EC2 instance you always need a key pair.
  # These are most easiest created in the AWS Console
  Parameter("KeyName") {
    Description "Name of an existing EC2 key pair to enable SSH access to the new EC2 instance"
    Type "String"
    Default "blogdemo"
  }

  # We might want direct SSH access to our servers for configuration
  # and other purposes. By default this is limited to our current VPC
  # as explained in my blogpost at
  # http://ig.nore.me/aws/2014/08/securing-ssh-access-with-cloudformation/
  Parameter("SshIp") {
    Description "IP address that should have direct access through SSH"
    Type "String"
    Default "10.42.0.0/24"
  }

  ##### Mappings section #####

  # Using a mapping we can easily keep different values grouped together
  # In this case, it's the different AMIs per region, as each region has
  # different identifiers for these regions. The one here is an Ubuntu 14.04
  # AMI eligible for the free tier. As AMIs are frequently replaced, please
  # check that this one is still valid.
  Mapping("AWSRegionArch2AMI", {
            "us-east-1" => { "AMI" => "ami-864d84ee" }
  })

  # A second mapping is for our subnet configuration. Before trying out this
  # template, please make sure you're not already running a VPC with this IP
  # range
  Mapping("SubnetConfig", {
      "VPC"     => { "CIDR" => "10.42.0.0/16" },
      "Public"  => { "CIDR" => "10.42.0.0/24" }
  })

  ##### VPC Section #####

  # As we don't want to depend on anything in this template,
  # we build the VPC infrastructure as well
  Resource("BabyVPC") {
    Type "AWS::EC2::VPC"
    # This is the first example of finding a value in a mapping
    Property("CidrBlock", FnFindInMap("SubnetConfig", "VPC", "CIDR"))
  }

  # We want a public subnet available
  Resource("PublicSubnet") {
    Type "AWS::EC2::Subnet"
    # If you referenced an existing VPC, you would put its id in here,
    # in this case however, we refer to the VPC resource we created above
    Property("VpcId", Ref("BabyVPC"))
    Property("CidrBlock", FnFindInMap("SubnetConfig", "Public","CIDR"))
  }

  # The gateways and routing tables are required to make sure we can connect
  # to the internet from the VPC
  Resource("InternetGateway") {
      Type "AWS::EC2::InternetGateway"
  }

  Resource("AttachGateway") {
       Type "AWS::EC2::VPCGatewayAttachment"
       Property("VpcId", Ref("BabyVPC"))
       Property("InternetGatewayId", Ref("InternetGateway"))
  }

  Resource("PublicRouteTable") {
    Type "AWS::EC2::RouteTable"
    Property("VpcId", Ref("BabyVPC"))
  }

  Resource("PublicRoute") {
    Type "AWS::EC2::Route"
    DependsOn "AttachGateway"
    Property("RouteTableId", Ref("PublicRouteTable"))
    Property("DestinationCidrBlock", "0.0.0.0/0")
    Property("GatewayId", Ref("InternetGateway"))
  }

  Resource("PublicSubnetRouteTableAssociation") {
    Type "AWS::EC2::SubnetRouteTableAssociation"
    Property("SubnetId", Ref("PublicSubnet"))
    Property("RouteTableId", Ref("PublicRouteTable"))
  }

  ##### Security Groups #####

  # While we can define the security parameters directly in the resource
  # the DSL allows us to separate them, thereby making it slightly more readable
  ec2SecurityIngres = Array.new

  # Only the ELB can connect through port 80 (http) to the EC2 instances
  ec2SecurityIngres.push({
    "IpProtocol" => "tcp",
    "FromPort" => "80",
    "ToPort" => "80",
    # here we reference a group that is defined later in the template
    "SourceSecurityGroupId" => Ref("ELBSecurityGroup")
  })

  # We limit SSH access to our servers to the value in the SshIp parameter
  ec2SecurityIngres.push({
    "IpProtocol" => "tcp",
    "FromPort" => "22",
    "ToPort" => "22",
    "CidrIp" => Ref("SshIp")
  })

  # We need this one more than once, so let's define it separately
  port80Open = [{
                  "IpProtocol" => "tcp",
                  "FromPort" => "80",
                  "ToPort" => "80",
                  "CidrIp" => "0.0.0.0/0"
                }]

  # We now create the actual instance security group
  Resource("InstanceSecurityGroup") {
    Type "AWS::EC2::SecurityGroup"
    # We can often provide tags as well for additional information. In this case
    # the "Name" tag is also displayed as the name of the resource in the Console
    Property("Tags", [{"Key" => "Name", "Value" => "Babysteps EC2"}])
    Property("VpcId", Ref("BabyVPC"))
    Property("GroupDescription" , templateName + " - EC2 instances: HTTP and SSH access")
    Property("SecurityGroupIngress", ec2SecurityIngres)
  }

  # We now create the actual instance security group
  Resource("ELBSecurityGroup") {
    Type "AWS::EC2::SecurityGroup"
    Property("Tags", [{"Key" => "Name", "Value" => "Babysteps ELB"}])
    Property("VpcId", Ref("BabyVPC"))
    Property("GroupDescription" , templateName + " - ELB: HTTP access")
    Property("SecurityGroupIngress", port80Open)
    Property("SecurityGroupEgress", port80Open)
  }

  ##### EC2 Section #####

  # We need to add all of our instances to the ELB, so we will put
  # the references in an array.
  babystepsServerRefs = Array.new

  (1..numberOfInstances).each do |instanceNumber|
    instanceName = "Babysteps#{instanceNumber}"
    # Instantiate the reference
    Resource(instanceName) {
      Type "AWS::EC2::Instance"
      # We have to define in which subnet the instances should be
      Property("SubnetId", Ref("PublicSubnet"))
      # Lets add a tag with the name so we can keep them apart
      Property("Tags", [{"Key" => "Name", "Value" => "#{templateName}-#{instanceNumber}"}])
      # Lets pick the correct AMI for this region
      Property("ImageId",
                FnFindInMap( "AWSRegionArch2AMI", Ref("AWS::Region"),"AMI"))
      # We finally get to use the instancetype parameter
      Property("InstanceType", Ref("InstanceType"))
      # And the keyname
      Property("KeyName", Ref("KeyName"))
      # The security group so we can access the servers
      Property("SecurityGroupIds", [Ref("InstanceSecurityGroup")])
      # The userdata is passed along to the server, in this case we use it
      # to install apache so the loadbalancer has something to look at
      Property("UserData", {
                          "Fn::Base64" =>
                            FnJoin("\n",[
                              "#!/bin/bash",
                              "apt-get install -y apache2"
                              ]
                          )})
    }
    # If we want to access the servers directly, we need to provide them
    # with an Elastic IP Address.
    Resource ("BabyIP#{instanceNumber}") {
      Type "AWS::EC2::EIP";
      Property("Domain", "vpc")
      Property("InstanceId", Ref(instanceName))
    }
    # Add the instance to the reference array
    babystepsServerRefs.push(Ref(instanceName))

    # Outputs show extra information in the Console, or when calling
    # describe-stacks.
    Output("#{instanceName}IpAddress") {
      # Using Fn::GettAtt you can get specific values from a resource
      Value FnGetAtt(instanceName, "PublicIp")
    }

  end

  ##### ELB Section #####

  # The Loadbalancer
  Resource("BabystepsLoadBalancer") {
    Type "AWS::ElasticLoadBalancing::LoadBalancer"
    # This too needs to be assigned to a subnet and security group
    Property("Subnets", [Ref("PublicSubnet")])
    Property("SecurityGroups", [Ref("ELBSecurityGroup")])
    # The listeners are for how it should pass things along, if we had an SSL
    # key for HTTPS access we would add that here as well.
    Property("Listeners" , [{
                                "LoadBalancerPort" => "80",
                                "InstancePort" => "80",
                                "Protocol" => "HTTP"
                              }])
    # The healthcheck configuration, based on which it decides to take out
    # EC2 instances or not.
    Property("HealthCheck" , {
                "Target" => "HTTP:80/index.html",
                "HealthyThreshold" => "3",
                "UnhealthyThreshold" => "5",
                "Interval" => "30",
                "Timeout" => "5"
              })
    # And finally we add the instances.
    Property("Instances", babystepsServerRefs)
  }

}