# Lab 1 - Kubernetes Essentials

## 1.1 - Pods, ReplicaSets and Deployments

The intent of this walkthrough is to familiarise you with the standard method of getting apps into Kubernetes: `Deployments`. However, it is important to understand the relationship between `Pods`, `ReplicaSets` and `Deployments`.

The container images we'll use for this lab are ones we'll keep using throughout the course. There are several different versions of our simple back-end image in AWS's public container registry.

### Task 1 - Spin up a Pod

1. Create a pod named `simple`, using the `public.ecr.aws/qa-wfl/qa-wfl/qakf/sbe:v1` image

<details><summary>show command</summary>
<p>

```bash
kubectl run simple --image=public.ecr.aws/qa-wfl/qa-wfl/qakf/sbe:v1
```

</p>
</details>


<br/>Example output:
```
pod/simple created
```

2. Get the new pod's IP address 

<details><summary>show command</summary>
<p>

```bash
kubectl get pods --output wide
#or
kubectl get pod simple --output=custom-columns=IP:.status.podIP --no-headers
```

</p>
</details>

<br/>Example output:
```
NAME     READY   STATUS    RESTARTS   AGE     IP         ...
simple   1/1     Running   0          3m59s   10.42.0.10 ...

#or

10.42.0.10
```

3. **cURL** the pod's IP address at port 8080

<details><summary>show command</summary>
<p>

```bash
curl 10.42.0.10:8080
```

</p>
</details>

<br/>Example output:
```
I am the backend service. I'm version 1!
```

### Task 2 - Create a YAMLfest

4. Let’s look at a PodSpec. Similar command to before, but we’re going to perform a `client`-side `dry-run` and output the result in YAML format to a file named pod.yaml. This is a convenient way to create a kubernetes manifest: 

<details><summary>show command</summary>
<p>

```bash
kubectl run hello --image=public.ecr.aws/qa-wfl/qa-wfl/qakf/sbe:v1 \ 
  --dry-run=client -o yaml > pod.yaml 
```

</p>
</details>
<br/>

5. Now examine the pod.yaml file. Note that there are a number of properties. Some of these are required and have been added by the api-server when we ran the pod,,some are optional. Note the API version, v1. Pods are part of the “core” kubernetes API. Pods have a “kind” of “Pod”. All k8s resources have a “kind”. Some metadata has also been added. The creationTimestamp is null because the pod was never actually created. A resources stanza has been added to the podspec (more on that much later on) and the pod has a status of null (again, because it was never created). The podspec section is the most important, because all of the controllers we’ll be looking at create and manage pods, somewhere in their manifest. 

<br/>

```yaml
apiVersion: v1 
kind: Pod 
metadata: 
  creationTimestamp: null 
  labels: 
    run: hello 
  name: hello 
spec: 
  containers: 
  - image: public.ecr.aws/qa-wfl/qa-wfl/qakf/sbe:v1 
    name: hello 
    resources: {} 
  dnsPolicy: ClusterFirst 
  restartPolicy: Always 
status: {} 
```

### Task 3 - Create a ReplicaSet

6. A Pod is fine, but we probably want to “guarantee” that we have at least one pod of our application running at all times. This is a job for a ReplicaSet! Create a file called rs.yaml and add the following content to it (there is no convenient shorthand for generating a ReplicaSet manifest): 

rs.yaml: 
```yaml
apiVersion: apps/v1 
kind: ReplicaSet 
metadata: 
  name: hello 
  labels: 
    app: hello 
spec: 
  replicas: 3 
  selector: 
    matchLabels: 
      app: hello 
  template: 
    metadata: 
      labels: 
        app: hello 
    spec: 
      containers: 
      - name: hello-world 
        image: public.ecr.aws/qa-wfl/qa-wfl/qakf/sbe:v1
```

Note the apiVersion is apps/v1. ReplicaSets aren’t part of the “core” API. We’re saying that we always want to have 3 pods running and the podspec from before is now nested in the ReplicaSet’s template stanza. 

7. Let’s create the ReplicaSet. Tell Kubernetes to `apply` this manifest to the cluster. 

<details><summary>show command</summary>
<p>

```bash
kubectl create -f rs.yaml 
```

</p>
</details>
<br/>

8. List your pods and replicasets ("rs" is the short name for replicaset) 

<details><summary>show command</summary>
<p>

```bash
kubectl get pod,rs 
```

</p>
</details>
<br/>

Example output:
```
NAME              READY   STATUS              RESTARTS   AGE 
pod/hello-4r2w5   0/1     ContainerCreating   0          11s 
pod/hello-m2hnb   1/1     Running             0          11s 
pod/hello-vr7wl   1/1     Running             0          11s 

NAME                    DESIRED   CURRENT   READY   AGE 
replicaset.apps/hello   3         3         2       11s 
```

Note that your pods now have auto-generated names and in the example output above, the Desired is 3 but the Ready is 2 because one pod is still in a ContainerCreating state. Your output may show 0-3 Ready pods depending on how fast you type! 

### Task 4 - Delete a Pod managed by a ReplicaSet

9. Now delete a pod (you’ll need to use one of the auto-generated names. I’m using the first one in my list) and then immediately list your pods and ReplicaSets again: 

<details><summary>show command</summary>
<p>

```bash
kubectl delete pod hello-4r2w5 --wait=false && kubectl get pods,rs
```

</p>
</details>
<br/>

We told kubectl not to wait for finalisers so hopefully we can see output similar to the following (again, it all depends on how fast you type!): 

Example output:
```bash
NAME              READY   STATUS              RESTARTS   AGE 
pod/hello-6sxx7   0/1     ContainerCreating   0          2s 
pod/hello-kmgdb   0/1     Terminating         0          61s 
pod/hello-rdbls   1/1     Running             0          114s 
pod/hello-vr7wl   1/1     Running             0          15m 

NAME                    DESIRED   CURRENT   READY   AGE 
replicaset.apps/hello   3         3         2       15m 
```

The ReplicaSet controller “noticed” almost immediately that we were down to 2 pods and told the api-server to run a new one. How does it know? The labels. In the spec there is a `matchLabels` stanza which is looking for a `label` of `app` with a value of `hello`. The podspec in the template specifies that each pod should be created with a label of app with a value of hello. The replicaset asks the api-server how many pods have that label and if the number is wrong, it tells the api-server to add or remove pods 

### Task 5 - Update the ReplicaSet

Now let’s try to update our replicaset to use v2 of the awesome application. 

10. Edit (or create a copy of) your rs.yaml file and change the image in the podspec to point to :v2 (it should be the very last line) 

```yaml
        image: public.ecr.aws/qa-wfl/qa-wfl/qakf/sbe:v2 
```
 

11. Now try to apply the new version. 

<details><summary>show command</summary>
<p>

```bash
kubectl apply -f rs2.yaml 
```

</p>
</details>
<br/>


12. Looks like it worked. But if you list all your pods again, you’ll see that they haven’t been recreated. 

13. Try finding the pods’ images by piping the output of `kubectl describe` to `grep` (this command is case sensitive): 

<details><summary>show command</summary>
<p>

```bash
kubectl describe pod | grep Image 
```

</p>
</details>
<br/>

They’re all running v1 still. 

A ReplicaSet will only apply this configuration change when it creates a new pod. Try deleting a pod manually again and then retry finding the pods’ images (the grep command above). You’ll now have one v2 and two v1s. 

14. Try scaling the ReplicaSet to zero and then back up to 3 again: 

<details><summary>show command</summary>
<p>

```bash
kubectl scale rs hello --replicas=0 

kubectl scale rs hello --replicas=3 
```

</p>
</details>
<br/>

You’ll now have 3 v2s if you redo the grep command. 

### Task 7 - Recreate the ReplicaSet

15. Delete the rs. 

<details><summary>show command</summary>
<p>

```bash
kubectl delete rs hello 
```

</p>
</details>
<br/>

So that’s fine and it might be desirable behaviour but we might want a controller that manages the rolling-out of new versions for us.

### Task 7 - Create a Deployment

16. Enter the `Deployment` controller. We’ll create a deployment using the handy command line shorthand again: 

<details><summary>show command</summary>
<p>

```bash
kubectl create deploy hello --image=public.ecr.aws/qa-wfl/qa-wfl/qakf/sbe:v1 --replicas=3 --dry-run=client -o yaml > dep.yaml
```

</p>
</details>
<br/>

17. Take a look at the manifest file. It looks an awful lot like the ReplicaSet yaml, except it has a `kind` of Deployment and there’s a strategy stanza as well. More about that later. Honest! 

Apply the manifest: 

<details><summary>show command</summary>
<p>

```bash
kubectl apply -f dep.yaml 
```

</p>
</details>
<br/>

18. And list your pods, replicasets and deployments: 

<details><summary>show command</summary>
<p>

```bash
kubectl get pod,rs,deploy 
```

</p>
</details>
<br/>

Example output: 
```
NAME                        READY   STATUS        RESTARTS   AGE 
pod/hello-c45c5786d-2vftd   1/1     Running       0          10s 
pod/hello-c45c5786d-rqbnk   1/1     Running       0          7s 
pod/hello-c45c5786d-zb5pw   1/1     Running       0          6s 

NAME                              DESIRED   CURRENT   READY   AGE 
replicaset.apps/hello-c45c5786d   3         3         3       10s 

NAME                    READY   UP-TO-DATE   AVAILABLE   AGE 
deployment.apps/hello   3/3     3            3           10s 
```
 
Now the replicaset has an autogenerated name and the pods have a double-autogenerated name! What’s happened is your deployment has created a replicaset and your replicaset is ensuring all the pods are present. 

19. Now update the version of the deployment to v2. You can modify the dep.yaml itself, or a copy of it, and apply that, or if you’re feeling vim-venturous you could do a `kubectl edit deploy hello`. It’s entirely up to you but however you do it, once you’ve done it, list your pods, rs and deployments again. 

<details><summary>show command</summary>
<p>

```bash
kubectl edit deploy hello
```

</p>
</details>
<br/>

<details><summary>show YAML</summary>
<p>

```yaml
        image: public.ecr.aws/qa-wfl/qa-wfl/qakf/sbe:v2 
```

</p>
</details>
<br/>

Example output: 
```
NAME                        READY   STATUS    RESTARTS   AGE 
pod/hello-c486c55bf-k2nwz   1/1     Running   0          15s 
pod/hello-c486c55bf-qwr42   1/1     Running   0          18s 
pod/hello-c486c55bf-t44rx   1/1     Running   0          16s 

NAME                              DESIRED   CURRENT   READY   AGE 
replicaset.apps/hello-c45c5786d   0         0         0       15m 
replicaset.apps/hello-c486c55bf   3         3         3       20s 

NAME                    READY   UP-TO-DATE   AVAILABLE   AGE 
deployment.apps/hello   3/3     3            3           15m 
```

We now have 2 rs. If you append `-o wide` onto the end of the get command, you’ll see that the `Deployment` is v2 and one of the `ReplicaSet`s is v1 (with a desired of 0) and the other is v2. Set the version of the deployment back to v1 and the two replicasets will be swapped again. The deployment doesn’t create a new replicaset for v1 because it knows it already has one. 

## 1.2 - Services
### Task 8 - expose the application

20. Finally, let’s make this tremendous application accessible to the outside world. That’s going to require a different kind of controller, a Service. Let’s just `expose` the deployment with a `type` of `NodePort` so we can cURL it. 

<details><summary>show command</summary>
<p>

```bash
kubectl expose deploy hello --type=NodePort 
```

</p>
</details>
<br/>

Example output: 
```
error: couldn't find port via --port flag or introspection 
See 'kubectl expose -h' for help and examples 
```

21. The reason for this error message is that I was lazy and couldn’t be bothered to add a port stanza to the podspec. I know it’s listening on port 8080, but Kubernetes doesn’t. The real solution is to add a port stanza to the spec, which should be considered a best practice, but we’ll do it the easy way, by specifying port 8080 in the `kubectl expose` command: 

<details><summary>show command</summary>
<p>

```bash
kubectl expose deploy hello --type=NodePort --port=8080
```

</p>
</details>
<br/>

You haven’t created an "Expose" controller, you’ve created a Service, which provides access to pods running inside the cluster via a single name or IP address. You can expose a pod, or a rs, or a deployment, or other kinds of controllers. In this case, you’ve created a NodePort service, which has exposed our service at a high-numbered port on every node in the cluster.

22. Let’s see if it has worked, by `get`ting the new service: 

<details><summary>show command</summary>
<p>

```bash
kubectl get service hello
```

</p>
</details>
<br/>

Example output:

```
NAME    TYPE       CLUSTER-IP     EXTERNAL-IP   PORT(S)          AGE
hello   NodePort   10.43.123.74   <none>        8080:31907/TCP   31s
```

<br/>

23. And test it by **cURL**ing the high-numbered NodePort at localhost:

<details><summary>show command</summary>
<p>

```bash
curl localhost:31907
```

</p>
</details>
<br/>

Example output:

```bash
I am the backend service. I'm version 2.
```

<br/>

24. Find out your kubernetes host's IP address and point your web browser at the NodePort's port number at that address:

<details><summary>show command</summary>
<p>

```bash
hostname -i
```

</p>
</details>
<br/>

25. Finally, delete the service and the deployment:

<details><summary>show command</summary>
<p>

```bash
kubectl delete service hello
kubectl delete deploy hello
```

</p>
</details>
<br/>

26. That's it, you're done! Let your instructor know that you've finished the lab.