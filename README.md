# macchina.io REMOTE - AWS Deployment

## About macchina.io REMOTE

[macchina.io REMOTE](https://macchina.io/remote) provides secure remote access to connected devices
via HTTP or other TCP-based protocols and applications such as secure shell (SSH) or
Virtual Network Computing (VNC). With macchina.io REMOTE, any network-connected device
running the macchina.io REMOTE Device Agent software (*WebTunnelAgent*)
can be securely accessed remotely over the internet from browsers, mobile apps, desktop,
server or cloud applications.

This even works if the device is behind a NAT router, firewall or proxy server.
The device becomes just another host on the internet, addressable via its own URL and
protected by the macchina.io REMOTE server against unauthorized or malicious access.
macchina.io REMOTE is a great solution for secure remote support and maintenance,
as well as for providing secure remote access to devices for end-users via web or
mobile apps.

Visit [macchina.io/remote](https://macchina.io/remote) to learn more and to register for a free account.
Specifically, see the [Getting Started](https://macchina.io/remote_signup.html) page and the
[Frequently Asked Questions](https://macchina.io/remote_faq.html) for
information on how to use the macchina.io REMOTE device agent.

There is also a [blog post](https://macchina.io/blog/?p=257) showing step-by-step instructions to connect a Raspberry Pi.


## About This Repository

This repository contains a documentation and sample configuration files to run the
macchina.io REMOTE server on AWS, using the following AWS services:

  - [Amazon EC2](https://aws.amazon.com/ec2/) to run the server
  - [Amazon RDS for MariaDB](https://aws.amazon.com/rds/mariadb/) to hold the data
  - [Amazon ElastiCache for Redis](https://aws.amazon.com/elasticache/redis/) for session management
  - [AWS Elastic Load Balancing](https://aws.amazon.com/elasticloadbalancing/) Application Load Balancer
  - [Amazon Route 53](https://aws.amazon.com/route53/) for wildcard DNS
  - [AWS Certificate Manager](https://aws.amazon.com/certificate-manager/) for the wildcard certificate


## Setting Up the AWS Services

### Setting Up an EC2 Linux Instance

We will start by creating an EC2 Linux (Ubuntu 18.04) instance which will
run the macchina.io REMOTE server (in a Docker container) and also
help us set up the environment. Specifically, we'll also use this instance
to set up the database schema later.

To create a EC2 Linux (Ubuntu 18.04) instance, go to
*Service > Compute > EC2* and click *Launch instance*.

Select the *Ubuntu Server 18.04 LTS (HVM)* 64-bit (x86) Amazon Machine Image.
In step 2, select a `t2.small` or `t2.medium` instance and
click *Next: Configure Instance Details*.

Select your default VPC (or a different VPC if desired). Make sure to use the same
VPC for all services you'll set up.

Click *Review & Launch*, then *Launch* on the *Review Instance Launch* screen.

After the instance has launched, SSH into it and run the following commands to
install the necessary software, which includes Docker, MariaDB and Redis clients.

```
$ sudo apt-get update && sudo apt-get upgrade -y
$ sudo apt-get install -y git docker.io mariadb-client redis-tools
```

The `ubuntu` user account must be added to the docker group in order for the docker
client program to communicate with the daemon:

```
$ sudo usermod -aG docker ubuntu
```

After the `usermod` command, log out and log in again to make it effective.

Also install *docker-compose* with:

```
$ sudo curl -L "https://github.com/docker/compose/releases/download/1.26.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
$ sudo chmod +x /usr/local/bin/docker-compose
```

Next, clone this repository to get access to the `createtables.sql` script
required later for setting up the database schema, as well as the files to
set up the Docker container.

```
$ git clone https://github.com/my-devices/meta-reflector-aws.git
```


### Setting Up an RDS for MariaDB Instance

In the AWS Console, go to *Services > Database > RDS* and click the *Create database*
button (under the *Create database* section) to set-up the new database.

Select *Standard Create* and *MariaDB*, as well as an appropriate template. For small to
medium-sized setups the *Free tier* template should be sufficient.

Enter a *DB instance identifier* name (in this document we will use `reflector`)
and fill out the *Master username* (we'll use the default `admin`).
Enter a *Master password* and *Confirm password*.

Under *Connectivity*, select the same VPC as the one for your EC2 instance created earlier.

All other settings can be left at their defaults for now.

Click *Create database* to finish and wait for the database instance to launch,
which may take a few minutes.


#### Enabling Triggers

Unfortunately, the default configuration of RDS does not allow triggers to be
created. To enable triggers, follow the following steps:

  1. Go to the Amazon RDS Console.
  2. Go to *Parameter groups*
  3. Click *Create parameter group* to create a new one. Name it `reflector` and
  enter a description.
  4. Select the newly created Parameter group and select *Edit* from *Parameter group actions*.
  5. Locate the `log_bin_trust_function_creators` parameter (enter it in the search box)
  and set it to `1`.
  6. Click *Save changes*.
  7. Go to the *Databases* tab and select the `reflector` database.
  8. Click *Modify*, go to *Database options* and under *DB parameter group*
  select the newly created `reflector` group.
  9. Scroll down and click *Continue*.
  10. Under *Scheduling of modifications*, select *Apply immediately* and click
  *Modify DB Instance*.
  11. Finally, reboot the instance (select instance in *Databases*, then click
  *Actions > Reboot*).


#### Creating the Database Schema

Setting up the database schema is actually a bit tricky as the macchina.io REMOTE Server
docker image expects that the database schema has been created prior to starting it.

For setting up the database schema, we'll use the EC2 Linux instance
created in the first step to launch the `mysql` client to create the database
schema and all tables required for the macchina.io REMOTE server.

> Note: you can also connect to the MariaDB database via a VPN (if configured), or by
giving the MariaDB instance public accessibility.

Then connect to the MariaDB instance and create a new database user `reflector`.
Enter the master password you have set for the database instance.

```
$ mysql -h reflector.cscny3pe5mxx.eu-central-1.rds.amazonaws.com -u admin -p
Enter password:
```

> Note: if you cannot connect to the MariaDB instance, check your security
group settings and verify that access to port 3306 is allowed.

Replace the host name (and, if necessary, username) with the values for your
specific instance.

Then run the following commands to create the `reflector` database and
a new user account and grant the user access to the `reflector` database:

```
MariaDB [(none)]> CREATE DATABASE reflector CHARACTER SET utf8;
MariaDB [(none)]> GRANT SELECT, INSERT, UPDATE, DELETE, INDEX, CREATE, DROP, TRIGGER, ALTER ON reflector.* TO 'reflector'@'%' IDENTIFIED BY 'reflector';
MariaDB [(none)]> quit
```

Finally, run the `createtables.sql` script to create the tables, indexes and triggers.

```
$ mysql -h reflector.cscny3pe5mxx.eu-central-1.rds.amazonaws.com reflector -u reflector -p <meta-reflector-aws/mysql/createtables.sql
```


### Setting Up an Amazon ElastiCache for Redis Instance

On the AWS Console, select *Services > Database > ElastiCache*, then *Get started*.
Select *Redis* as cluster engine, and enter a suitable name (e.g., `reflector-redis`).
Set the *Number of replicas* to zero and uncheck *Multi-AZ*.

Under *Advanced Redis settings*, select *Create new* for *Subnet group* and
select the correct *VPC ID* and check the subnet you'd like the Redis instance to be located in.
Also enter a suitable *Name* for the subnet group, e.g. `redis-subnet-group`.

Then click *Create*. Creating the Redis instance may take a few minutes.

Make sure you can connect to the Redis instance from the Linux machine, by running
`redis-cli`:

```
$ redis-cli -h reflector-redis.tw1u9f.0001.euc1.cache.amazonaws.com -p 6379
```

If you cannot connect, check the security group settings and allow access to port 6379.


### Setting Up the macchina.io REMOTE Server Container

To set-up the macchina.io REMOTE server Docker container, log-in to the EC2 instance
created in the first step and change directory to the `meta-reflector-aws`
directory cloned from GitHub.
Open the `docker-compose.yml` file in a text editor of your choice and
add the correct values for `REFLECTOR_DOMAIN`, `MYSQL_HOST` and `REDIS_HOST`.
For `REFLECTOR_DOMAIN`, enter the domain name you want the macchina.io REMOTE server to
run on, e.g. `demo.my-devices.net`.
For `MYSQL_HOST`, enter the value of your RDS MariaDB endpoint, e.g.
`reflector.cscny3pe5mxx.eu-central-1.rds.amazonaws.com`.
For `REDIS_HOST`, enter the value of your ElastiCache Redis endpoint host name,
e.g. `reflector-redis.tw1u9f.0001.euc1.cache.amazonaws.com` (do not include the
port number, which is part of the *Primary Endpoint* string displayed for the
Redis cluster).

Your `docker-compose.yml` file should look like this:

```
version: '3.0'
services:
  reflector:
    build: reflector
    restart: always
    ports:
      - "8000:8000"
    environment:
      REFLECTOR_DOMAIN: demo.my-devices.net
      REFLECTOR_LICENSE: /home/reflector/etc/reflector.license
      HTTP_PORT: 8000
      MYSQL_DATABASE: reflector
      MYSQL_USERNAME: reflector
      MYSQL_PASSWORD: reflector
      MYSQL_HOST: reflector.cscny3pe5mxx.eu-central-1.rds.amazonaws.com
      REDIS_HOST: reflector-redis.tw1u9f.0001.euc1.cache.amazonaws.com
      LOGCHANNEL: file
      LOGPATH: /home/reflector/var/log/reflector.log
    volumes:
      - logvolume:/home/reflector/var/log

volumes:
  logvolume:
```

Also make sure to replace the license file in `reflector/reflector.license` with
your own one.

Then, run:

```
$ docker-compose up -d
```

to start the macchina.io REMOTE server. You can verify that the server has started
correctly by looking at the log file with:

```
$ sudo cat /var/lib/docker/volumes/meta-reflector-aws_logvolume/_data/reflector.log
```

Or, to follow the log file:

```
$ sudo tail -f /var/lib/docker/volumes/meta-reflector-aws_logvolume/_data/reflector.log
```


### Setting Up DNS via Route 53

On the AWS Console, select *Services > Networking & Content Delivery > Route 53*.
Click on *Hosted zones* and use one of your existing zones or create a new one
for the domain the macchina.io REMOTE server will be using.
In this example we're using a zone named `my-devices.net`. You have to use
a different zone that matches the domain your server is running on.
The zone will be required in the next step to validate the Certificate
created by AWS Certificate Manager.


### Setting Up the Application Load Balancer

The final step is setting up the load balancer, including DNS and wildcard certificates.

Select *Services > EC2*, then *Load Balancing > Load Balancers*.

Click *Create Load Balancer*, then, under *Application Load Balancer*, click *Create*.
Under *Name*, enter `reflector-alb`.

Under *Listeners*, select *HTTPS* for the existing listener.
Under *Availability Zones*, select the correct VPC and select at least two availability
zones.

Click *Next: Configure Security Settings* to continue.

The next step is creating a TLS certificate for the load balancer. We'll do this
using AWS Certificate Manager.

For *Certificate type*, select *Choose a certificate from ACM (recommended)*,
then click *Request a new certificate from ACM*.

The ACM *Request a certificate* page will open in a new tab.
On it, enter the wildcard domain name (we'll use `*.demo.my-devices.net`; replace this
with your own domain). Then click *Add another name to this certificate* and enter
`demo.my-devices.net` (or whatever matches your domain).

Under *Select validation method*, select *DNS validation* and click *Next*.
Under *Add tags*, click *Review* (we won't be adding any tags at this point).
Then click *Confirm and request*.

The last step is *Validation*. If you have created a corresponding zone in Route 53 earlier,
you can click *Create record in Route 53* for each of the two domains and AWS will
automatically set up the DNS entries required for validation.

After the validation status changes to *Success*, click *Continue*.

Then, go back to the *Create Load Balancer* page and click the refresh button
next to the *Certificate name* field. The field should update with your new
certificate.

For *Security policy*, select `ELBSecurityPolicy-FS-2018-06`.

Next, select the *Security group*. Use the same one you have used for the EC2 Linux
instance.

Click *Next: Configure Routing*.

Under *Target group*, select *New target group* (default), and enter a suitable
*Name* (e.g., `reflector`). As *Target type*, select *instance*.
Leave *Protocol* at *HTTP* and enter *Port* number `8000` (the port the macchina.io REMOTE
server is running on), as configured in the `docker-compose.yml` file.

Click *Next: Register Targets*.

Select the EC2 instance created in the first step in the list and click *Add to registered*.

Click *Next: Review*, verify the settings are correct, then click *Create*.

As a final step, the *Idle timeout* of the ALB must be increased.
Select the ALB instance, under *Description*, locate *Attributes* and click
*Edit attributes*. Set *Idle timeout* to `3600` and click *Save*.


#### Health Check

You can configure a health check on the ALB. The path `/my-devices/health.json` on the
macchina.io REMOTE server can be used as an endpoint for the ALB health check.


### Setting Up DNS via Route 53 (Part 2)

The final step is adding the DNS `CNAME` entries for the new ALB instance.
In Route 53, create two CNAME entries in your newly created zone, one for the
base domain (in our case `demo.my-devices.net`), and one for the wildcard domain (in our case
`*.demo.my-devices.net`). Both entries should point to the domain name of the
ALB instance just created (e.g. `reflector-alb-974178111.eu-central-1.elb.amazonaws.com`).


### Wrapping Up

You should now be able to log-in to your new macchina.io REMOTE server
instance by navigating to the domain your server runs on, e.g. https://demo.my-devices.net
As a first step after logging in, you should change the password for the `admin` user.
Then, connect your first device via [`WebTunnelAgent`](https://github.com/my-devices/sdk)
(also available as [Docker image](https://hub.docker.com/repository/docker/macchina/device-agent))
or the [macchina.io REMOTE Gateway](https://github.com/my-devices/gateway)
([Docker image](https://hub.docker.com/repository/docker/macchina/rmgateway)).


## Troubleshooting

The most likely troubles will arise from VPC and security group settings preventing
the services to communicate properly.

Make sure all services (EC2 instance, EC2 ALB, RDS MariaDB, ElastiCache Redis)
are in the same VPC.

Review that the security group settings in
your setup allow the following communication:

  - The EC2 Linux instance must be able to connect to the RDS MariaDB instance
    (on port 3306) and the ElastiCache Redis instance (on port 6379).
  - The ALB must be able to connect to port 8000 on the EC2 Linux instance.
  - The ALB HTTPS port must be reachable from anywhere.

Furthermore, make sure the ALB idle timeout is set to a value greater than
the default 60 seconds. We recommend setting it to one hour (3600 seconds).
The value should be greater than the remote timeout (`webtunnel.remoteTimeout` property)
configured in the macchina.io REMOTE device agent (`WebTunnelAgent`).
