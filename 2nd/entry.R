library(rmarkdown)
library(Biobase)
library(SingleCellExperiment)
library(doParallel)
library(foreach)
library(cluster)
library(peco)
# addition
library(circular)

args = commandArgs()
print('Commandline arguments are...')
print(args)

args1 = args[length(args)-1]
args2 = args[length(args)]

render(paste0(args1,'.Rmd'), output_file = paste0('./results/', paste0(args2, '.pdf')))
