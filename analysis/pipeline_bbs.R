library(drake)
library(MATSS)
library(LDATS)
library(matssldats)
source(here::here("fxns", "lda_wrapper.R"))
## make sure the package functions in MATSS and matssldats are loaded in as
##   dependencies
expose_imports(MATSS)
expose_imports(matssldats)


seed <- seq(from = 2, to = 6, by = 2)

ncpts <- c(0, 1)

ntopics <- c(2, 3, 4, 7, 11)

forms <- c("intercept", "time")

rt <- 6
rg <- 11

pipeline <- drake_plan(
  rdat = target(get_bbs_dat(rt, rg),
                transform = map(rt = !!rt, rg = !!rg)),
  dat = target(subset_data(rdat, n_segs = 40, sequential = T, buffer = 2, which_seg = this_seg),
               transform = cross(rdat, this_seg = !!c(1:40))),
  models = target(ldats_wrapper(dat, seed = sd, ntopics = k, ncpts = cpts, formulas = form, nit = 1000),
                  transform = cross(dat, sd = !!seed, k = !!ntopics,
                                    cpts = !!ncpts, form = !!forms)),
  ll_dfs = target(get_timestep_ll(models),
                  transform = map(models)), 
  composite_ll = target(combine_timestep_lls(list(ll_dfs), ncombos = 10000),
                        transform = combine(ll_dfs, .by = rdat)),
  list_ll = target(list(ll_dfs),
                   transform = combine(ll_dfs))
)


## Set up the cache and config
db <- DBI::dbConnect(RSQLite::SQLite(), here::here("drake", "drake-cache-bbs.sqlite"))
cache <- storr::storr_dbi("datatable", "keystable", db)


## View the graph of the plan
if (interactive())
{
  config <- drake_config(pipeline, cache = cache)
  sankey_drake_graph(config, build_times = "none")  # requires "networkD3" package
  vis_drake_graph(config, build_times = "none")     # requires "visNetwork" package
}


## Run the pipeline
nodename <- Sys.info()["nodename"]
if(grepl("ufhpc", nodename)) {
  library(future.batchtools)
  print("I know I am on SLURM!")
  ## Run the pipeline parallelized for HiPerGator
  future::plan(batchtools_slurm, template = "slurm_batchtools.tmpl")
  make(pipeline,
       force = TRUE,
       cache = cache,
       cache_log_file = here::here("drake", "cache_log.txt"),
       verbose = 2,
       parallelism = "future",
       jobs = 200,
       caching = "master") # Important for DBI caches!
} else {
  # Run the pipeline on a single local core
  system.time(make(pipeline, cache = cache, cache_log_file = here::here("drake", "cache_log.txt")))
}

