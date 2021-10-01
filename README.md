# renv_to_docker

![renv_to_docker](https://user-images.githubusercontent.com/35414366/135584120-2be79766-a8dc-46ba-86df-8897c19cce4e.png)

This is a use case of using docker with renv.

**renv** is a package developed by [Kevin Ushey](https://github.com/kevinushey) at Rstudio which for all intents and purposes, is meant to replace Packrat.

renv is meant to increase reproducibility on R projects, while making the process of setup less strenuous on your computer and sanity. It does this by recording the R version and the package versions, just like other environment managers like conda.

**Docker** is a well-known tool in containerizing tools and apps. Rather than using a full-fledged VM which take time to set up, docker aims to reduce both the time in building it and the computational cost to your machine by utilizing the OS of your computer to do the work rather than having a fully operational OS built in.

Now, the question is, how do we combine them both?

## Motivation

Two major benefits exist in using renv with docker.

1. (Beefing up reproducibility) While renv saves the versions of each packages and R, there are other factors that may affect the final results such as the operating system and system libraries. Thus, having a *base* for a project in the form of docker may be beneficial.

2. (Cross-platform snapshot) Since docker is meant to be run on any system, saving your project through docker will allow it be run at any given time on any machine as long as your machine can run docker. Containerization also effectively isolates your project environment as a *snapshot* from any changes to your local system.

## Why renv (and not Packrat or Conda)?

If you switch out renv with any of the two (Packrat, Conda), you can still say the same thing in the motivation section. So why do we use renv?

### Packrat

Packrat had a fatal flaw in everyday use; initialization took way too long. This is also mentioned in the comparison notes seen [here](https://rstudio.github.io/renv/articles/renv.html#comparison-with-packrat-1);

> renv no longer attempts to explicitly download and track R package source tarballs within your project. This was a frustrating default that operated under the assumption that you might later want to be able to restore a project’s private library without access to a CRAN repository. In practice, this is almost never the case, and the time spent downloading + storing the package sources seemed to outweigh the potential reproducibility benefits.

I personally test a lot of tools, and having to wait forever to initialize a project was enough of a deterrant after a few tries.

### Conda

This is more anecdotal. I personally never had much success in using R with Conda. And since you can't install things on the fly through Rstudio while using it with Conda, I never really took to using it. But if you use R with python, it might be a good idea to invest in Conda as well.

## Other renv + docker implemenetations

There a few tips out there regarding the simultaneous use of both.

renv itself has a [recommendation](https://rstudio.github.io/renv/articles/docker.html) laid out on their github page. This particular recommendation puts forward a way to use the system cache of renv to build the docker image in such a way that the docker will use the pre-installed packages on your host instead of downloading them from scratch.

While this is undoubtedly quicker, this is problematic for me since it will have to use my local host's packages that are for my host OS (macOS). Not only that, this is not self-contained.

Robert Dahl Jacobsen has an interesting [take on this](https://github.com/robertdj/renv-docker) by dividing the process into two steps; one to 'install image' and one to 'finalize image'. To quote him;

> - The "install image": The first image consists only of the prerequisites for the projects. When running a container from this image it can install R packages in the format it needs inside the container and save them to {renv}'s cache on the host through a mount.
> - The "final image": The second image copies the project along with dependencies from the host into the image.

This is great. I just happen to prefer not depending on my host for storage, and would rather take care of all processes using <code>renv.lock</code> file alone.

## renv_to_docker

My solution is similar to Robert, but my first *base* image will be just that; a base.

This base image will contain all the base packages required for a particular project. Base image is then meant to be used as a starting point for all following iterations of the project, with additions to packages if required.

We are working with the file tree as follows. See the upcoming dockerfiles and commands for further info.

```bash
.
├── 1st
│   ├── 2nd_build.sh
│   ├── Dockerfile_build
│   ├── entry.R
│   ├── peco_demo.Rmd
│   └── run.sh
├── 2nd
│   ├── 2nd_build.sh
│   ├── Dockerfile_build
│   ├── entry.R
│   ├── peco_demo_plot.Rmd
│   ├── run.sh
│   └── sce-final.rds
├── README.md
└── base
    ├── 1st_build.sh
    ├── Dockerfile_install
    └── renv.lock
```


### Base image dockerfile (folder:<code>/base</code>)

```dockerfile
FROM rocker/verse:4.1.1

# General taking care of user checkpoints
RUN mkdir /project
RUN chown root:root /project
USER root

# Set working directory
WORKDIR /project
# Set a global variable
ENV RENV_VERSION=0.11.0
# Copy renv.lock file
COPY ./renv.lock /project/renv/

# Install remotes package from CRAN
RUN R -e "install.packages('remotes', repos = c(CRAN = 'https://cloud.r-project.org'))"
# Install renv (version specified previously) through remotes
RUN R -e "remotes::install_github('rstudio/renv@${RENV_VERSION}')"

# Source: joelnitta, https://github.com/joelnitta/docker-packrat-example/blob/master/Dockerfile
RUN R -e "renv::consent(provided = TRUE)"
RUN R -e "renv::restore(lockfile = './renv/renv.lock')" 
```

As you can see, the base is an image built on top of rocker/verse (you can edit which version of R to use). Then the dockerfile instructs the build to copy the host <code>renv.lock</code> file and use this to directly install packages in this image.

```bash
docker build \
-t sc/base:demo \
-f Dockerfile_install .
```

The above shell script will then build this image following the specifications of the dockerfile <code>Dockerfile_install</code>. As you can see, I have named this base image <code>base:demo</code>.

### A use-case for base (folder:<code>/1st</code>)

```dockerfile
FROM sc/base:demo

# Set global variables
ENV rmd peco_demo
ENV output peco_demo

# Create results directory
RUN mkdir -p /project/results

# Copy files from the host
COPY ./entry.R .
COPY "./${rmd}.Rmd" .

# Run command (run R)
CMD /usr/local/bin/Rscript --vanilla entry.R $rmd $output
```

Now it's time to use the base image. I'm using this to render a rmarkdown file named <code>peco_demo.Rmd</code>. As you can see, there is no installation required for the packages as it was all taken care of during the first image build. As such, the build and run is exponentially faster. Note that the package loading and render parameters are taken care of by a separate R file called <code>entry.R</code>.

```bash
docker build \
-t sc/peco_demo \
-f Dockerfile_build .
```

The above shell script will build this second image on top of base following the specifications of the dockerfile <code>Dockerfile_build</code>.

### Expanding the base (folder:<code>/2nd</code>)

Now, consider a scenario where you'd like to add more packages onto this image, say add a package for doing an additional plotting.

```dockerfile
FROM sc/peco_demo

# Set global variables
ENV rmd peco_demo_plot
ENV output peco_demo_plot

# Create results directory
RUN mkdir -p /project/results

# Copy files from the host
COPY ./entry.R .
COPY "./${rmd}.Rmd" .
COPY ./sce-final.rds .

# Run command (run R)
RUN R -e "install.packages('circular')"
RUN R -e "renv::snapshot()"
CMD /usr/local/bin/Rscript --vanilla entry.R $rmd $output
```

From the above dockerfile, you can see the addition of a package named <code>circular</code>. This is then saved to the lock file in the image by <code>renv::snapshot()</code>. Then build as usual using the following command.

```bash
docker build \
-t sc/peco_demo_plot \
-f Dockerfile_build .
```

## Further work

While the newly added packages can be saved to the image <code>renv.lock</code>, this means that you would need to keep this image around if you plan on expanding further on this particular package addition.

Also, if you were to decide to add a significant package that will be used throughout the project, you may need to revamp the base image.

Regardless, the chain lives on as the created docker image down the chain will no longer require the base to propagate. But this does make maintaining them a hassle.

Conclusion is that this is my particular use case where I do not have a lot of loose ends from a project. But if you happen to have a fairly large one where there are many versions, the approach by Robert may very well be preferable due to having a central repository of your renv cache.

## Reference

Source of some code snippets are mentioned in the dockerfile.

The code from [peco](https://github.com/jhsiao999/peco) was used for the example rmarkdown. As this was downloaded not from CRAN but from devtools, it showcases renv handling such jobs as well as the typical packages found in CRAN.
