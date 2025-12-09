FROM ubuntu:latest
LABEL authors="Artem P"

RUN apt update && apt install wget curl -y
RUN wget https://downloads.mongodb.com/compass/mongodb-mongosh_2.5.9_amd64.deb
RUN dpkg -i mongodb-mongosh_2.5.9_amd64.deb || apt install -f -y

# Copy initialization script
COPY init-cluster.sh /scripts/init-cluster.sh
RUN chmod +x /scripts/init-cluster.sh

ENTRYPOINT ["/scripts/init-cluster.sh"]