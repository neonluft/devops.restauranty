# Welcome to my final Ironhack Project Restauranty #

In this readme file, you will understand how to replicate the deployment for yourself. 

# STEP 1. CREATING THE CLUSTER #

switch to /terra_infra

```bash
 ./up.sh <your-name> 
```
this will take about 15 minutes of your time. 

# STEP 2. DEPLOYING THE MANIFESTS AND EVERYTHING ELSE NEEDED FOR THIS PROJECT#

this step takes the docker images that i have built during this project. You can of course take the time to build them yourself and subsitute your images in the corresponding .yaml files

execute the script from the projects root directory

```bash
./apply_eks.sh
```
this will apply the nginx ingress, the k8s manifests (deployment and service for all microservices + MongoDB)
this script will also add Loki/Prometheus/Grafana and its necessary yaml files to the cluster. (Remember to use port-forwarding for Grafana to the port 3000 for easy localhost access)



