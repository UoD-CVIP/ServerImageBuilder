# ServerImageBuilder
You will need to have some experience of:
- Docker (bonus points for Docker BuildKit)
- JupyterHub admin / config

The repo builds docker images for GPU backed deep learning frameworks.
The images are then used as workspace containers for JupyterHub on the Deep Learning servers in Computing.
We currently have 3 functional GPU images for:
- Tensorflow (v 1.14.x -> 2.1.0)
- PyTorch (1.4.0)
- Matlab (r2018a -> r2019b)

The CVIP versions of these images live at `https://hub.docker.com/uodcvip/`. 
This means the DL servers do not have to rely on some centralised build process.
Additional CPU only images can be pulled directly from the JupyterHub DockerHub repo. 
TODO: we may want to start building some custom CPU only images for languages like `C++` or `java` etc.

### Building images
Use the `run-prod.sh` script to build the images. For Tensorflow images:
```bash
./run.sh tensorflow
```

Matlab is a special case as it requires an extra argument network address for licensing:
```bash
./run.sh matlab <PORT-NUMBER>@<DNS-ADDRESS>
```

### Updating available images
Update the `<framework>_image_tags.txt.<version>` file with new tags for the base image files.
Then run the script as above.

### How it works
There are 3 main stages to each build:
1. Install base OS dependencies
2. Configure the jupyter environment
3. Configure the framework environment/build






