# ServerImageBuilder
The repo builds the docker images used as workspace containers for JupyterHub on the CVIP servers in Computing.

### Knowledge Requirements
You will need to have some experience of:
- General sysadmin
- Docker (bonus points for Docker BuildKit, multi-stage builds)
- JupyterHub admin / config
- Shell scripting


We use the base images created by each deep learning framework (Matlab, tensorflow and pytorch) as a
starting point.
Our images add the necessary components and dependencies for running with Jupyterhub and doing
things like SSH etc on the CVIP servers.
All our images are available at `https://hub.docker.com/uodcvip/`.

### Building images
Use the `run-prod.sh` script to build the images. For Tensorflow images:
```bash
./run.sh tensorflow
```

Matlab is a special case as it requires an extra argument network address for licensing:
```bash
./run.sh matlab <PORT-NUMBER>@<DNS-ADDRESS>
```

Hint: To find the correct matlab licensing argument run `env | grep MLM` inside an already built
matlab image.

### Updating available images
Update the `<framework>_image_tags.txt.<version>` file with new tags for the base image files.
Then run the script as above.

### How it works
There are 3 main stages to each build:
1. Install base OS dependencies
2. Configure the jupyter environment
3. Configure the framework environment/build
4. Add the entrypoint scripts for JupyterHub and SSH.

The JupyterHub entrypoint scripts are *required* to get images running correctly -- i.e. switching
to the OS user account and mounting their home directory.





