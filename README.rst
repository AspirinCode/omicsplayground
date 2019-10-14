Omics Playground: Explore Omics Data Freely
================================================================================

The Omics Playground is a comprehensive self-service platform platform 
for visualization, analytics and exploration of Big Omics Data. 
It allows users to apply a multitude of state-of-the-art analysis tools 
to their own data to explore and discover underlying biology in a short time.

The platform offers a unique combination of features that 
distinguishes it from the other analytics platforms currently available. 
We believe that data preprocessing (primary analysis) and statistical 
testing (secondary analysis) are now well established, and the most challenging 
task is currently data interpretation (tertiary analysis) that often takes the 
longest time but where actual insights can be gained. Therefore the Omics 
Playground focuses strongly on tertiary analysis while providing good support 
for secondary analysis.

The overview of the platform is shown in the figure below. It consists of
two main components. The first component addresses the data
importing and preprocessing, which includes preparing the input data, filtering,
normalising and precomputing of statistics for some analyses. The second part is
composed of the online interface, which supports the real-time visualisation and
interaction with users. The interface is subdivided into Basic and Expert modes
to provide a customisable experience suited to each user's background.
More detailed information and feature explanation of Omics Playground is 
available in the `online documentation <https://omicsplayground.readthedocs.io>`__.

.. figure:: docs/figures/overview.png
    :align: center
    :width: 90%



Installation
================================================================================

You can either run the platform from the source code, or download the
docker image.


Run from source code
--------------------------------------------------------------------------------

Omics Playground is implemented in R using the `Shiny Server
<https://shiny.rstudio.com/>`__ web application framework. You will
need R and Shiny Server installed to run Omics Playground.

The source code of the platform is available on 
`GitHub <https://github.com/bigomics/omicsplayground>`__. You can 
download the latest release of the software by cloning
the repository. Below, we explain the steps required to set up the platform from
the source code:

1. Download or clone the GitHub repository to a location in your ``PATH``::

    git clone https://github.com/bigomics/omicsplayground.git
    
2. Be sure you have installed all necessary R packages by running the files in the ``/R`` folder::

    Rscript requirements.R
    
3. Similarly, run the following command in the ``/scripts`` folder to build the datasets::

    Rscript run-all.R

.. note::

    Building the datasets can vary from minutes to a couple of hours depending on their sizes.

4. Change the current directory into the ``/shiny`` folder and execute the following command
   to run the platform::

    R -e "rmarkdown::run(shiny_args=list(launch.browser=TRUE))"

   If you have Shiny Server installed you can create a link to the
   shiny folder in the system-wide shiny-server apps folder or in your
   ShinyApps user folder.

   
    
Run using the Docker file
--------------------------------------------------------------------------------
The docker file of the platform is available on `Docker Hub 
<https://hub.docker.com/r/bigomics/omicsplayground>`__.
Follow the steps below to set up a running platform from the docker file:

1. Pull the docker image using the command::

    docker pull bigomics/omicsplayground
    
2. Then run the docker with::

    docker run --rm -p 80:3838 bigomics/omicsplayground.
    
3. Open ``http://localhost`` in your browser to run the platform.

.. note::

    The docker image requires about 5GB hard disk space.
    
    