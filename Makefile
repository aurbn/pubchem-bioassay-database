cores = 1 
all: working/summarystats.txt

clean:
	rm -rf working/*

##########################################
# download external dependencies 
# Note: all external files should go here
##########################################

# download all of PubChem Bioassay
working/bioassayMirror: src/mirrorBioassay.sh
	mkdir -p $@
	$^ $@

# download uniprot ID mappings
working/uniprot_id_mapping.dat.gz:
	mkdir -p working
	wget ftp://ftp.uniprot.org/pub/databases/uniprot/current_release/knowledgebase/idmapping/idmapping.dat.gz -O $@

# download protein target sequences
working/targets.fasta: working/bioassayDatabase.sqlite
	echo "SELECT DISTINCT target FROM targets WHERE target_type = \"protein\";" | sqlite3 $< | xargs -I '{}' wget -O - "http://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=protein&id={}&rettype=fasta&retmode=text" >> $@

# download Pfam HMM data
working/Pfam-A.hmm:
	wget -O $@.gz ftp://ftp.ebi.ac.uk/pub/databases/Pfam/releases/Pfam29.0/Pfam-A.hmm.gz
	gunzip $@.gz
	hmmpress $@

# download kClust linux binary
working/kClust:
	wget -O $@ ftp://toolkit.lmb.uni-muenchen.de/pub/kClust/kClust
	chmod u+x $@

##########################################
# build database
##########################################

# extract GI-> uniprot ID mappings to uncompressed text file
working/gi_uniprot_mapping.dat: working/uniprot_id_mapping.dat.gz
	zcat $< | awk '{if ($$2 == "GI") print $$0;}' > $@

# load assays into database
working/bioassayDatabase.sqlite: src/buildBioassayDatabase.R working/bioassayMirror
	$^ proteinsOnly $@

# compute target HMMs
working/domainsFromHmmscan: working/Pfam-A.hmm working/targets.fasta
	hmmscan --tblout working/domainsFromHmmscan --cpu $(cores) --noali $^

# extract domains from HMM results
working/domainsFromHmmscanTwoCols: working/domainsFromHmmscan
	awk '{print $$2 " " $$3}' $^ > $@

# load domain data into database
working/bioassayDatabaseWithDomains.sqlite: src/loadDomainData.R working/targets.fasta working/domainsFromHmmscanTwoCols working/bioassayDatabase.sqlite
	cp working/bioassayDatabase.sqlite $@
	src/loadDomainData.R working/targets.fasta working/domainsFromHmmscanTwoCols $@

# use kClust to cluster proteins by sequence
working/targetClusters: working/kClust working/targets.fasta
	mkdir $@ 
	$< -i working/targets.fasta -d $@ -s 0.52 -M 16000MB

# load UniProt mappings into database
working/databaseWithTargetTranslations.sqlite: src/loadTranslations.R working/bioassayDatabaseWithDomains.sqlite working/gi_uniprot_mapping.dat working/targetClusters
	cp working/bioassayDatabaseWithDomains.sqlite $@
	$< working/gi_uniprot_mapping.dat working/targetClusters $@

# turn on indexing
working/indexedBioassayDatabase.sqlite: working/databaseWithTargetTranslations.sqlite 
	cp $< $@
	echo "CREATE INDEX IF NOT EXISTS activity_cid ON activity (cid);" | sqlite3 $@
	echo "CREATE INDEX IF NOT EXISTS activity_aid ON activity (aid);" | sqlite3 $@
	echo "CREATE INDEX IF NOT EXISTS targets_aid ON targets (aid);" | sqlite3 $@
	echo "CREATE INDEX IF NOT EXISTS targets_target ON targets (target);" | sqlite3 $@
	echo "CREATE INDEX IF NOT EXISTS targetTranslations_target ON targetTranslations (target);" | sqlite3 $@

# load species annotations for assays
working/bioassayDatabaseWithSpecies.sqlite: src/annotateSpecies.R working/indexedBioassayDatabase.sqlite
	cp working/indexedBioassayDatabase.sqlite $@
	$< $@

# create symbolic link to final database file
working/pubchemBioassay.sqlite: working/bioassayDatabaseWithSpecies.sqlite 
	ln -s bioassayDatabaseNoDuplicates.sqlite $@ 

# summarize database contents in a text file
working/summarystats.txt: src/computeStats.R working/pubchemBioassay.sqlite working/bioassayMirror
	$^ $@
