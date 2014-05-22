# This script will take
## An expression dataset (using ensembl_id or probeset identifiers)
## A table of phenotypic data of samples
## A character vector of the factor to analyse

# The script will evaluate the power of each gene expression level to 
# discriminate the samples according to the expected phenotypic factor

# The script will summarise genes annotated to a same GO term
# to evaluate the power of each GO term to discriminate the samples according 
# to the expected phenotypic factor

# The script will return
## A table ranking GO terms according to their power to discriminate samples
## A table mapping  GO terms and genes to one another
## A table ranking genes according to their power to discriminate samples
## The factor used to calculate scores
## Some parameters used to perform the analysis

# Downstream analyses
## Function to filter the resulting scores to GO terms passing given criteria
## Function to list the genes annotated to a GO term
## Function to see the scores of the genes annotated to a GO term
## Function to cluster samples according to a list of genes
## Function to heatmap the samples according to a list of genes
## Function to see the distribution of scores for all GO terms (histogram)
## Function to see the quantiles of scores across all GO terms
## Function to filter the results for GO terms by various criteria
## Two function to visualise the expression profile of a gene across a X-variable and 
### grouped by a Y-factor (plot by gene_id or by gene_symbol)
## Function to visualise the univariate effect of each factor on the grouping of samples
## Function to reorder the GO terms and genes by either rank or score metrics.

# Dependencies
## Internet connection (biomaRt)
## Packages grid, Biobase, biomaRt, stringr, ggplot2, RColorBrewer, gplots, VennDiagram


GO_analyse = function(expr_data, phenodata, f, biomart_dataset="", microarray="",
                      method="randomForest", rank.by="rank",
                      do.trace=100, ntree=1000, mtry=ceiling(2*sqrt(nrow(expr_data))), 
                      ...){
  # if less than 4 genes in data will cause mtry lrager than number ofgenes which is then impossible
  # however, who uses a transcriptomics dataset of 4 genes?
  if (nrow(expr_data) < 4){
    stop("Too few genes in dataset: ", nrow(expr_data))
  }
  # If phenodata is not a Biobase object, the function pData would fail later
  if (!class(phenodata) == "AnnotatedDataFrame"){
    stop("Invalid type: phenodata is not an AnnotatedDataFrame object.")
  }
  # The random forest requires the factor (f) to be an actual R factor
  if (!any(class(pData(phenodata)[,f]) == "factor")){
    stop("pData(phenodata)[,f] must be an actual R factor. See method factor()")
  }
  # The random forest requires all levels of the factor to have at least one sample
  if (any(table(pData(phenodata)[,f]) == 0)){
    stop("One level of pData(phenodata)[,f] has no correspondig sample.
         Please remove that level.")
  }
  # If the user gave an invalid method name (allow specific abbreviations)
  if (!method %in% c("randomForest", "anova", "rf", "a")){
    stop("Invalid method: ", method)
  }
  # If the user gave an invalid ranking method for GO terms and genes
  if (!rank.by %in% c("rank","score")){
    stop("Invalid ranking method: ", rank.by)
  }
  # If the user gave an invalid factor name
  if (!f %in% colnames(pData(phenodata))){
    stop("Invalid factor name: ", f)
  }
  # if the user did not give a dataset name
  if (biomart_dataset == ""){
    # if the user did not give a microarray value
    if (microarray == ""){
      # automatically detect both
      # fetch the first gene id in the given expression dataset
      sample_gene = rownames(expr_data)[1]
      cat("First gene identifier in dataset:", sample_gene, fill=TRUE)
      # Try to find an appropriate biomaRt ensembl dataset from the gene prefix
      mart = mart_from_ensembl(sample_gene)
      # if the gene id has not an identifiable ensembl gene id prefix
      if (!class(mart) == "Mart"){
        # Try to find an appropriate biomaRt microarray dataset from the gene prefix
        microarray_match = microarray_from_probeset(sample_gene)
        # if the gene id has an identifiable microarray gene id prefix
        if (!is.null(nrow(microarray_match))){
          # connect to biomart and set the microarray variable
          cat("Looks like microarray data.", fill=TRUE)
          cat("Loading detected dataset", microarray_match$dataset,
              "for detected microarray", microarray_match$microarray,
              "...", fill=TRUE)
          microarray = microarray_match$microarray
          biomart_dataset = microarray_match$dataset
          mart = biomaRt::useMart(biomart="ensembl", dataset=biomart_dataset)
        }
        # if the gene id does not have an identifiable microarray gene id prefix
        else{
          # stop the program and throw an error
          stop("Cannot guess origin of dataset:
               Please use \"biomart_dataset=\" and/or \"microarray=\" arguments.")
        }
      }
      # if the gene id has an identifiable ensembl gene id prefix
      # then, the connection to the mart is already established
      # leave microarray to "" to imply that we don't work with microarray data
    }
    # if the user gave a microarray name
    else{
      # check if it exists
      if (!microarray %in% microarray2dataset$microarray){
        stop("Invalid microarray value. See data(microarray2dataset)")
      }
      # if it is unique to a dataset (some microarray have the same column name
      if(sum(microarray2dataset$microarray == microarray) == 1){
        biomart_dataset = microarray2dataset[microarray2dataset$microarray == microarray, "dataset"]
        cat("Loading requested microarray", microarray, "from detected dataset", biomart_dataset, "...", fill=TRUE)
        mart = biomaRt::useMart(biomart="ensembl", dataset=biomart_dataset)
        # Leave microarray to the current valid value
      }
      # if the microarray does not exist in the dataset
      else if(sum(microarray2dataset$microarray == microarray) == 0){
        stop("Microarray name not recognised. See data(microarray2dataset).")
      }
      # if the microarray name exists in multiple datasets
      else{
        cat("Multiple datasets possible:", fill=TRUE)
        print(microarray2dataset[microarray2dataset$microarray == microarray, c("dataset", "microarray")])
        stop("Cannot guess dataset.
             Please use \"biomart_dataset=\" argument.")
      }  
    }
  }
  # if the user gave a biomart_dataset value
  else{
    # Check that it exists
    if (!biomart_dataset %in% prefix2dataset$dataset){
      stop("Invalid biomart_dataset value. See data(prefix2dataset)")
    }
    cat("Using biomart dataset", biomart_dataset, fill=TRUE)
    # if the user did not give a microarray name
    if (microarray == ""){
      # Check if looks like microarray
      # fetch the first gene id in the given expression dataset
      sample_gene = rownames(expr_data)[1]
      cat("First gene identifier in dataset:", sample_gene, fill=TRUE)
      microarray_match = microarray_from_probeset(sample_gene)
      # if the data matches a known microarray pattern
      if (!is.null(nrow(microarray_match))){
        # connect to biomart and set the microarray variable
        cat("Looks like microarray data.", fill=TRUE)
        # if the dataset/microarray pair exists
        if (microarray_match$dataset == biomart_dataset){
          cat("Loading annotations for detected microarray",
              microarray_match$microarray, "for requested dataset",
              biomart_dataset, "...", fill=TRUE)
          mart = biomaRt::useMart(biomart="ensembl", dataset=biomart_dataset)
          microarray = microarray_match$microarray
          print(mart)
        }
        # if the dataset/microarray pair does no exist
        else{
          # The dataset exists, the data matches a microarray
          # but not a microarray of the dataset
          cat("Detected microarray", microarray_match$microarray,
               "inexisting in requested dataset", biomart_dataset,
               ". Possible datasets are:")
          return(microarray_match)
        }
      }
      # if the data does not match a microarray pattern
      else{
        cat(sample_gene, "gene identifier in expression data cannot\
  be resolved to a microarray. Assuming ensembl gene identifiers.", fill=TRUE)
      }
      # If it does not look like microarray
      # assume it is ensembl annotations
      # therefore do nothing more
      # in both cases load the requested mart dataset
      cat("Loading requested dataset", biomart_dataset, "...", fill=TRUE)
      mart = biomaRt::useMart(biomart="ensembl", dataset=biomart_dataset)
    }
    # if the user gave a microarray name
    else{
      # Check that the pair dataset/microarray exists
      if (!biomart_dataset %in% microarray2dataset[microarray2dataset$microarray == microarray, "dataset"]){
        stop("There is no microarray ", microarray, " in dataset ", biomart_dataset)
      }
      cat("Loading requested microarray", microarray, "from requested biomart dataset", biomart_dataset, fill=TRUE)
      mart = biomaRt::useMart(biomart="ensembl", dataset=biomart_dataset)
    }
  }
  print(mart)
  #  if working with ensembl gene identifiers
  if (microarray == ""){
    # Prepare a mapping table between gene identifiers and GO terms
    cat("Fetching ensembl_gene_id/GO_id mappings from BioMart ...", fill=TRUE)
    GO_genes = biomaRt::getBM(attributes=c("ensembl_gene_id", "go_id"), mart=mart)
  }
  # if working with microarray probesets
  else{
    # Prepare a mapping table between gene identifiers and GO terms
    cat("Fetching probeset/GO_id mappings from BioMart ...", fill=TRUE)
    GO_genes = biomaRt::getBM(attributes=c(microarray, "go_id"), mart=mart)
  }
  # Rename the first column which could be ensembl_id or probeset_id
  colnames(GO_genes)[1] = "gene_id"
  # Remove over 1,000 rows where the go_id is ""
  GO_genes = GO_genes[GO_genes$go_id != "",]
  # Remove rows where the gene_id is "" (happens)
  GO_genes = GO_genes[GO_genes$gene_id != "",]
  # Prepare a table of all the GO terms in BioMart (even if no gene is annotated to it)
  cat("Fetching GO_terms description from BioMart ...", fill=TRUE)
  all_GO = biomaRt::getBM(attributes=c("go_id", "name_1006", "namespace_1003"),
                 mart=mart)
  # Remove the GO terms which is ""
  all_GO = all_GO[all_GO$go_id != "",]
  # Run the analysis with the desired method
  cat("Analysis using method", method ,"on factor", f,"for", nrow(expr_data),
      "genes. This may take a few minutes ...", fill=TRUE)
  if (method %in% c("randomForest", "rf")){
    ## Similarly to the previous anova procedure (see below)
    # Run the randomForest algorithm
    rf = randomForest::randomForest(x=t(expr_data), y=pData(phenodata)[,f],
                                    importance=TRUE,
                                    do.trace=do.trace,
                                    ntree=ntree,
                                    mtry=mtry,
                                    ...)
    # Save the importance value used as score for each gene in a data.frame
    res = data.frame("Score" = randomForest::importance(rf)[,ncol(randomForest::importance(rf))])
  }
  else if (method %in% c("anova", "a")){
    # A vectorised calculation the F-value of an ANOVA used as score for each gene
    res = data.frame("Score" = apply(X=expr_data,
                                       MARGIN=1,
                                       FUN=function(x){oneway.test(formula=expr~group,
                                                                   data=cbind(expr=x,
                                                                              group=Biobase::pData(phenodata)[,f]))$statistic}))
  }
  # Calculate the rank of each gene based on their score
  res$Rank = rank(-res$Score, ties.method="min")
  # Summary statistics by GO term
  ## Merge the table mapping GOterm to genes with the score of each gene, twice:
  # - First merge the tables while keeping all gene/GO mappings, even for genes absent of the dataset
  # This will allow average F values to be calculated on the basis of all ensembl genes annotated to 
  # the GO term, even if not in the dataset (genes absent are given score of 0 and rank of max(rank)+1)
  # Merge GO/gene mapping with randomForest results
  GO_gene_score_all = merge(x=GO_genes, y=res, by.x="gene_id", by.y="row.names", all.x=TRUE)
  # Replace NAs (genes absent from dataset but present in biomaRt) by 0 (minimal valid value)
  GO_gene_score_all[is.na(GO_gene_score_all$Score), "Score"] = 0
  # In addition, all genes absent from the dataset are assigned 1 + (the maximum rank of the genes in the dataset)
  GO_gene_score_all[is.na(GO_gene_score_all$Rank), "Rank"] = max(res$Rank) + 1
  # - Second, merge the tables keeping only the genes present in the dataset
  # This will be used to count how many genes are present in dataset for each GO term
  GO_gene_score_data = merge(x=GO_genes, y=res, by.x="gene_id", by.y="row.names")
  # Results can now be summarised by aggregating rows with same GOterm
  # Appends gene annotations to rows of res
  cat("Fetching gene description from BioMart ...", fill=TRUE)
  #  if working with ensembl gene identifiers
  if (microarray == ""){
    genes_score = merge(x=res, all.x=TRUE,
                        y=biomaRt::getBM(attributes=c("ensembl_gene_id", "external_gene_id", "description"),
                                filters="ensembl_gene_id",
                                values=rownames(res),
                                mart=mart),
                        by.x="row.names",
                        by.y="ensembl_gene_id")
  }
  # if working with microarray probesets
  else{
    # Prepare a mapping table between gene identifiers and GO terms
    genes_score = merge(x=res, all.x=TRUE, 
                        y=biomaRt::getBM(attributes=c(microarray, "external_gene_id", "description"),
                                filters=microarray,
                                values=rownames(res),
                                mart=mart),
                        by.x="row.names",
                        by.y=microarray)
    # In the case of microarray, probesets can be annotated to multiple gene symbols
    # for each probeset, keep only the first row (we're losing one possible annotation here)
    # But otherwise, we will not be able to make unique row names of gene
    # Moreover, keeping the same probeset twice (because of two annotated symbols) would
    # affect the averaging of scores for GO terms. Each probeset should only be there once anyway
    genes_score = genes_score[ !duplicated(genes_score$Row.names), ]
  }
  # Put the ensembl identifier back as the row name
  rownames(genes_score) = genes_score$Row.names
  genes_score$Row.names = NULL
  cat("Merging score into result table ...", fill=TRUE)
  # Total number of genes in the dataset annotated to each GO term
  GO_scores = merge(x=aggregate(gene_id~go_id, data=GO_gene_score_data, FUN=length), y=all_GO, by="go_id", all.y=TRUE)
  colnames(GO_scores)[2] = "data_count"
  GO_scores[is.na(GO_scores$data_count), "data_count"] = 0
  # Total number of genes annotated to each GO term in BioMart (not necessarily in dataset)
  GO_scores = merge(x=aggregate(Score~go_id, data=GO_gene_score_all, FUN=length), y=GO_scores, by="go_id", all.y=TRUE)
  colnames(GO_scores)[2] = "total_count"
  # Average score (denominator being the total of genes by GO term in BioMart) being tested
  GO_scores = merge(x=aggregate(Score~go_id, data=GO_gene_score_all, FUN=mean), y=GO_scores, by="go_id", all.y=TRUE)
  colnames(GO_scores)[2] = "ave_score"
  ## Average rank (denominator being the total of genes by GO term in BioMart) being tested
  # (+) robust for GO terms with several genes
  GO_scores = merge(x=aggregate(Rank~go_id, data=GO_gene_score_all, FUN=mean), y=GO_scores, by="go_id", all.y=TRUE)
  colnames(GO_scores)[2] = "ave_rank"  
  # Notes of other summary metrics tested:
  ## Sum: (-) biased toward general GO terms annotated for many thousands of genes (e.g. "protein binding")
  ## Max.F.values: (+) insensitive to number of genes annotated for GO term
  #                (-) many GO terms sharing the same gene are tied (-) biased by outliers
  # Most top ranked GO terms according to the average F value contain a single gene
  # But this bias can easily be attenuated by filtering for GO terms with a minimal number of genes
  if (rank.by == "rank"){
    # Rank the genes by increasing rank
    genes_score = genes_score[order(genes_score$Rank),]
    # Rank the GO terms by decreasing average rank
    GO_scores = GO_scores[order(GO_scores$ave_rank),]
  }
  else if (rank.by == "score"){
    # Rank the genes by increasing rank
    genes_score = genes_score[order(genes_score$Score, decreasing=TRUE),]
    # Same for the GO terms (by average)
    GO_scores = GO_scores[order(GO_scores$ave_score, decreasing=TRUE),]
  }
  # Return the results of the analysis
  if (method %in% c("randomForest", "rf")){
    return(list(GO=GO_scores, mapping=GO_genes, genes=genes_score, factor=f, method=method, ntree=ntree, mtry=mtry))
  }
  else if (method %in% c("anova", "a")) {
    return(list(GO=GO_scores, mapping=GO_genes, genes=genes_score, factor=f, method=method))
  }
}

mart_from_ensembl = function(sample_gene){
  # If the gene id starts by "ENS" (most cases, except 3 handled separately below)
  if (length(grep(pattern="^ENS", x=sample_gene))){
    # Extract the full prefix
    prefix = stringr::str_extract(sample_gene, "ENS[[:upper:]]+")
    # If the ENS* prefix is in the table 
    if (prefix %in% prefix2dataset$prefix){
      # load the corresponding biomart dataset
      cat("Looks like ensembl gene identifier.", fill=TRUE)
      cat("Loading detected dataset", prefix2dataset[prefix2dataset$prefix == prefix,]$dataset,
          "...", fill=TRUE)
      return(biomaRt::useMart(biomart="ensembl",
                     dataset=prefix2dataset[prefix2dataset$prefix == prefix,]$dataset))
    }
    # Otherwise return FALSE
    else{
      cat("Did not recognise a valid ensembl gene identifier.", fill=TRUE)
      return(FALSE)
    }
  }
  # If the gene id starts with "WBgene"
  else if (length(grep(pattern="^WBGene", x=sample_gene))) {
    # load the corresponding biomart dataset
    cat("Looks like ensembl gene identifier.", fill=TRUE)
    cat("Loading detected dataset celegans_gene_ensembl ...", fill=TRUE)
    return(biomaRt::useMart(biomart="ensembl", dataset="celegans_gene_ensembl"))
  }
  # If the gene id starts with "FBgn"
  else if (length(grep(pattern="^FBgn", x=sample_gene))) {
    # load the corresponding biomart dataset
    cat("Looks like ensembl gene identifier.", fill=TRUE)
    cat("Loading detected dataset dmelanogaster_gene_ensembl ...", fill=TRUE)
    return(biomaRt::useMart(biomart="ensembl", dataset="dmelanogaster_gene_ensembl"))
  }
  # If the gene id starts with "Y"
  else if (length(grep(pattern="^Y", x=sample_gene))) {
    # load the corresponding biomart dataset
    cat("Looks like ensembl gene identifier.", fill=TRUE)
    cat("Loading detected dataset scerevisiae_gene_ensembl ...", fill=TRUE)
    return(biomaRt::useMart(biomart="ensembl", dataset="scerevisiae_gene_ensembl"))
  }
  # If the gene id does not match any known ensembl gene id prefix, return an error and stop
  else{
    cat("Did not recognise an ensembl gene identifier.", fill=TRUE)
    return(FALSE)
  }
}

microarray_from_probeset = function(sample_gene){
  matches = c()
  # For each pattern thought to be unique to a microarray
  for (pattern in microarray2dataset$prefix[microarray2dataset$unique]){
    # if the pattern matches the sample gene
    if (length(grep(pattern=pattern, x=sample_gene))){
      # add the pattern to a vector 
      matches = c(matches, pattern)
    }
  }
  # if the vector length is at least 1 (unlikely to ever be more than 1 if patterns do not overlap)
  if (length(matches)){
    # return (dataset, microarray) to the main function to build mapping tables
    return(microarray2dataset[microarray2dataset$prefix == matches[1],
                                           c("dataset","microarray")])
  }
  # If the sample gene was not recognised in the unique ones,
  # check whether it may be an ambiguous identifier
  # For each unique pattern known to be found in multiple microarrays
  for (pattern in unique(microarray2dataset$prefix[!microarray2dataset$unique])){
    # if the pattern matches the sample gene
    if (length(grep(pattern=pattern, x=sample_gene))){
      # add the pattern to a vector 
      matches = c(matches, pattern)
    }
  }
  # if vector contains at least 1 pattern
  if (length(matches)){
    # print sample, first pattern, and list of possible microarray
    cat(sample_gene, "matches pattern", matches[1], "found in multiple microarrays:", fill=TRUE)
    print(microarray2dataset[microarray2dataset$prefix == matches[1], 
                              c("dataset","microarray")], row.names=FALSE)
    return(FALSE)
  }
  # if no known microarray pattern matches, return FALSE
  else{
    cat("Did not recognise microarray data.", fill=TRUE)
    return(FALSE)
  }
}