


OS := $(shell uname -s)
ARCH := $(shell uname -p)
EPOCH=$(shell date +'%s')
YEAR=$(shell date +'%Y')

#
# Automatically get the username and pasword
#
ifeq ($(OS), Darwin)
	# Find the username and password from the OSX keychain. Works if you have logged into Garmin Connect from Safari or you manually set it.
	# If your using iCloud Keychaion, you have to copy the entry from the iCloud keychain to the login keychain using KeychainAccess.app.
	GC_USER ?= $(shell security find-internet-password -s sso.garmin.com | egrep acct | egrep -o "[A-Za-z]*@[A-Za-z.]*" )
	GC_PASSWORD ?= $(shell security find-internet-password -s sso.garmin.com -w)
	GC_DATE ?= $(shell date -v-1y +'%m/%d/%Y')
else
	# store the username and password in ~/.garmindb.conf ?
	GC_DATE ?= $(shell date -d '-1 year' +'%m/%d/%Y')
endif
GC_DAYS ?= 365


HEALTH_DATA_DIR=$(HOME)/HealthData
FIT_FILE_DIR=$(HEALTH_DATA_DIR)/FitFiles
FITBIT_FILE_DIR=$(HEALTH_DATA_DIR)/FitBitFiles
MSHEALTH_FILE_DIR=$(HEALTH_DATA_DIR)/MSHealth
DB_DIR=$(HEALTH_DATA_DIR)/DBs
TEST_DB_DIR=/tmp/DBs
BACKUP_DIR=$(HEALTH_DATA_DIR)/Backups
MONITORING_FIT_FILES_DIR=$(FIT_FILE_DIR)/$(YEAR)_Monitoring
SLEEP_FILES_DIR=$(HEALTH_DATA_DIR)/Sleep
ACTIVITES_FIT_FILES_DIR=$(FIT_FILE_DIR)/Activities
WEIGHT_FILES_DIR=$(HEALTH_DATA_DIR)/Weight
RHR_FILES_DIR=$(HEALTH_DATA_DIR)/RHR

BIN_DIR=$(PWD)/bin

TEST_DB=$(TMPDIR)/test.db

DEFAULT_SLEEP_START=22:00
DEFAULT_SLEEP_STOP=06:00

#
# Master targets
#
all: update_dbs

setup: update deps

update: submodules_update
	git pull --rebase

submodules_update:
	git submodule init
	git submodule update

deps_tcxparser:
	cd python-tcxparser && sudo python setup.py install --record files.txt

clean_deps_tcxparser:
	cd python-tcxparser && sudo cat files.txt | xargs rm -rf

deps: deps_tcxparser
	sudo pip install --upgrade sqlalchemy
	sudo pip install --upgrade requests
	sudo pip install --upgrade python-dateutil || true

clean_deps: clean_deps_tcxparser
	sudo pip uninstall sqlalchemy
	sudo pip uninstall selenium
	sudo pip uninstall python-dateutil

clean:
	rm -rf *.pyc
	rm -rf Fit/*.pyc
	rm -rf HealthDB/*.pyc
	rm -rf GarminDB/*.pyc
	rm -rf FitBitDB/*.pyc


#
# Fitness System independant
#
SUMMARY_DB=$(DB_DIR)/summary.db
$(SUMMARY_DB): $(DB_DIR)

summary: mshealth_summary fitbit_summary garmin_summary

build_dbs: garmin_dbs mshealth_summary fitbit_summary

rebuild_dbs: clean_dbs build_dbs

update_dbs: new_garmin

clean_dbs: clean_mshealth_db clean_fitbit_db clean_garmin_dbs clean_summary_db

clean_summary_db:
	rm -f $(SUMMARY_DB)

$(DB_DIR):
	mkdir -p $(DB_DIR)

$(BACKUP_DIR):
	mkdir -p $(BACKUP_DIR)

backup: $(BACKUP_DIR)
	zip -r $(BACKUP_DIR)/$(EPOCH)_dbs.zip $(DB_DIR)


#
# Garmin
#

## test monitoring
$(TEST_DB_DIR):
	mkdir -p $(TEST_DB_DIR)

test_monitoring_clean:
	rm -rf $(TEST_DB_DIR)

TEST_FIT_FILE_DIR=$(HEALTH_DATA_DIR)/TestFitFiles
test_monitoring_file: $(TEST_DB_DIR)
	python import_garmin.py -e --fit_input_file "$(MONITORING_FIT_FILES_DIR)/20053386096.fit" --sqlite $(TEST_DB_DIR)
#	python import_garmin.py -t -e --fit_input_file "$(TEST_FIT_FILE_DIR)" --sqlite $(TEST_DB_DIR) && \
	python analyze_garmin.py --analyze --dates  --sqlite $(TEST_DB_DIR)

##  monitoring
GARMIN_MON_DB=$(DB_DIR)/garmin_monitoring.db
$(GARMIN_MON_DB): $(DB_DIR) import_monitoring

clean_monitoring_db:
	rm -f $(GARMIN_MON_DB)

$(MONITORING_FIT_FILES_DIR):
	mkdir -p $(MONITORING_FIT_FILES_DIR)

download_monitoring: $(MONITORING_FIT_FILES_DIR)
	python download_garmin.py -d $(GC_DATE) -n $(GC_DAYS) -u $(GC_USER) -p $(GC_PASSWORD) -m "$(MONITORING_FIT_FILES_DIR)"

import_monitoring: $(DB_DIR)
	for dir in $(shell ls -d $(FIT_FILE_DIR)/*Monitoring*/); do \
		python import_garmin.py -e --fit_input_dir "$$dir" --sqlite $(DB_DIR); \
	done

download_new_monitoring: $(MONITORING_FIT_FILES_DIR)
	python download_garmin.py -l --sqlite $(DB_DIR) -u $(GC_USER) -p $(GC_PASSWORD) -m "$(MONITORING_FIT_FILES_DIR)"

import_new_monitoring: download_new_monitoring
	for dir in $(shell ls -d $(FIT_FILE_DIR)/*Monitoring*/); do \
		python import_garmin.py -e -l --fit_input_dir "$$dir" --sqlite $(DB_DIR); \
	done

## activities
GARMIN_ACT_DB=$(DB_DIR)/garmin_activities.db
$(GARMIN_ACT_DB): $(DB_DIR) import_activities

clean_activities_db:
	rm -f $(GARMIN_ACT_DB)

$(ACTIVITES_FIT_FILES_DIR):
	mkdir -p $(ACTIVITES_FIT_FILES_DIR)

TEST_ACTIVITY_ID=1589795363
test_import_activities: $(DB_DIR) $(ACTIVITES_FIT_FILES_DIR)
	python import_garmin_activities.py -t1 -e --input_file "$(ACTIVITES_FIT_FILES_DIR)/$(TEST_ACTIVITY_ID).fit" --sqlite $(DB_DIR)

test_import_tcx_activities: $(DB_DIR) $(ACTIVITES_FIT_FILES_DIR)
	python import_garmin_activities.py -t1 -e --input_file "$(ACTIVITES_FIT_FILES_DIR)/$(TEST_ACTIVITY_ID).tcx" --sqlite $(DB_DIR)

test_import_json_activities: $(DB_DIR) $(ACTIVITES_FIT_FILES_DIR)
	python import_garmin_activities.py -e --input_file "$(ACTIVITES_FIT_FILES_DIR)/activity_$(TEST_ACTIVITY_ID).json" --sqlite $(DB_DIR)

import_activities: $(DB_DIR) $(ACTIVITES_FIT_FILES_DIR)
	python import_garmin_activities.py -e --input_dir "$(ACTIVITES_FIT_FILES_DIR)" --sqlite $(DB_DIR)

import_new_activities: $(DB_DIR) $(ACTIVITES_FIT_FILES_DIR) download_new_activities
	python import_garmin_activities.py -e -l --input_dir "$(ACTIVITES_FIT_FILES_DIR)" --sqlite $(DB_DIR)

download_new_activities: $(ACTIVITES_FIT_FILES_DIR)
	python download_garmin.py --sqlite $(DB_DIR) -u $(GC_USER) -p $(GC_PASSWORD) -a "$(ACTIVITES_FIT_FILES_DIR)" -c 10

download_all_activities: $(ACTIVITES_FIT_FILES_DIR)
	python download_garmin.py --sqlite $(DB_DIR) -u $(GC_USER) -p $(GC_PASSWORD) -a "$(ACTIVITES_FIT_FILES_DIR)"

## generic garmin
GARMIN_DB=$(DB_DIR)/garmin.db
$(GARMIN_DB): $(DB_DIR) garmin_config import_sleep import_weight import_rhr

clean_garmin_summary_db:
	rm -f $(GARMIN_SUM_DB)

clean_garmin_dbs: clean_garmin_summary_db clean_monitoring_db clean_activities_db
	rm -f $(GARMIN_DB)

## sleep
$(SLEEP_FILES_DIR):
	mkdir -p $(SLEEP_FILES_DIR)

import_sleep: $(DB_DIR)
	python import_garmin.py -e --sleep_input_dir "$(SLEEP_FILES_DIR)" --sqlite $(DB_DIR)

import_new_sleep: download_sleep
	python import_garmin.py -e -l --sleep_input_dir "$(SLEEP_FILES_DIR)" --sqlite $(DB_DIR)

download_sleep: $(SLEEP_FILES_DIR)
	python download_garmin.py -d $(GC_DATE) -n $(GC_DAYS) -u $(GC_USER) -p $(GC_PASSWORD) -S "$(SLEEP_FILES_DIR)"

## weight
$(WEIGHT_FILES_DIR):
	mkdir -p $(WEIGHT_FILES_DIR)

import_weight: $(DB_DIR)
	python import_garmin.py -e --weight_input_dir "$(WEIGHT_FILES_DIR)" --sqlite $(DB_DIR)

import_new_weight: download_weight import_weight

download_weight: $(DB_DIR) $(WEIGHT_FILES_DIR)
	python download_garmin.py --sqlite $(DB_DIR) -u $(GC_USER) -p $(GC_PASSWORD) -w "$(WEIGHT_FILES_DIR)"

## rhr
$(RHR_FILES_DIR):
	mkdir -p $(RHR_FILES_DIR)

import_rhr: $(DB_DIR)
	python import_garmin.py -e --rhr_input_dir "$(RHR_FILES_DIR)" --sqlite $(DB_DIR)

import_new_rhr: download_rhr import_rhr

download_rhr: $(DB_DIR) $(RHR_FILES_DIR)
	python download_garmin.py --sqlite $(DB_DIR) -u $(GC_USER) -p $(GC_PASSWORD) -r "$(RHR_FILES_DIR)"

## digested garmin data
GARMIN_SUM_DB=$(DB_DIR)/garmin_summary.db
$(GARMIN_SUM_DB): $(DB_DIR) garmin_summary

garmin_summary:
	python analyze_garmin.py --analyze --dates --sqlite $(DB_DIR)

new_garmin: import_new_monitoring import_new_activities import_new_weight import_new_sleep import_new_rhr garmin_summary

garmin_config:
	python analyze_garmin.py -S$(DEFAULT_SLEEP_START),$(DEFAULT_SLEEP_STOP)  --sqlite /Users/tgoetz/HealthData/DBs

garmin_dbs: $(GARMIN_DB) $(GARMIN_MON_DB) $(GARMIN_ACT_DB) $(GARMIN_SUM_DB)


#
# FitBit
#
FITBIT_DB=$(DB_DIR)/fitbit.db
$(FITBIT_DB): $(DB_DIR) import_fitbit_file

clean_fitbit_db:
	rm -f $(FITBIT_DB)

import_fitbit_file: $(DB_DIR)
	python import_fitbit_csv.py -e --input_dir "$(FITBIT_FILE_DIR)" --sqlite $(DB_DIR)

fitbit_summary: $(FITBIT_DB)
	python analyze_fitbit.py --sqlite $(DB_DIR) --dates

fitbit_db: $(FITBIT_DB)


#
# MS Health
#
MSHEALTH_DB=$(DB_DIR)/mshealth.db
$(MSHEALTH_DB): $(DB_DIR) import_mshealth

clean_mshealth_db:
	rm -f $(MSHEALTH_DB)

$(MSHEALTH_FILE_DIR):
	mkdir -p $(MSHEALTH_FILE_DIR)

import_mshealth: $(DB_DIR)
	python import_mshealth_csv.py -e --input_dir "$(MSHEALTH_FILE_DIR)" --sqlite $(DB_DIR)

mshealth_summary: $(MSHEALTH_DB)
	python analyze_mshealth.py --sqlite $(DB_DIR) --dates

mshealth_db: $(MSHEALTH_DB)
