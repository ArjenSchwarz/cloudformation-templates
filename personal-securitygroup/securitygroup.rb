  CloudFormation {
  AWSTemplateFormatVersion "2010-09-09"

  Description "Security group for personal access only"

  Parameter("AccessIP") {
    Description "IP address that should have direct access"
    Type "String"
    Default "10.0.0.0/24"
  }

  # The VPC in which we use this Security Group
  vpcId = "vpc-a817cfcd"
  # The ports we want access to
  ports = [22, 80, 443]

  secgroupIngres = []

  ports.each do | portnumber |
    secgroupIngres.push({
      "IpProtocol" => "tcp",
      "FromPort" => "#{portnumber}",
      "ToPort" => "#{portnumber}",
      "CidrIp" => Ref("AccessIP")
    })
  end

  Resource("InstanceSecurityGroup" ) {
    Type "AWS::EC2::SecurityGroup"
    Property("VpcId", vpcId)
    Property("Tags", [{"Key" => "Name", "Value" => "Personal access"}])
    Property("GroupDescription" , "SSH and HTTP(S) access from my current IP Address")
    Property("SecurityGroupIngress", secgroupIngres)
  }
}
