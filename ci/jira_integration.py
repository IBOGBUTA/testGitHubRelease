#!/usr/bin/python3
'''JIRA integration for the build step in the pipeline.

- Gets list of stories, tasks and bugs that are part of the build (to add
  to release notes)
- Sets JIRA bugs produced in a build to integrated.

IMPORTANT: it relies on filter already being in place in JIRA to find the
tickets. See the code for the fiters.
'''
import datetime as dt
from datetime import timedelta
import argparse
import os
import sys
import re
from jira import JIRA
from jira import JIRAError
from dotenv import load_dotenv

# Allow lower case "constants" with pylint
# pylint: disable=invalid-name

SUCCESS = 0
FAIL = 2

JIRA_FROM_UNIFY = False

if JIRA_FROM_UNIFY:
    TO_INTEGRATED = '81'
    user = os.getenv('JIRA_USER')
    token = os.getenv('JIRA_PASSWD')
    jira_options = {
        'server': 'https://jira.dev.global-intra.net:8443',
        'verify': False,
    }
    proxies={"http": "http://172.26.192.28:3128", "https": "http://172.26.192.28:3128"}
else:
    TO_INTEGRATED = '3'
    user = os.getenv('JIRA_USER2')
    token = os.getenv('JIRA_TOKEN2')
    jira_options = { 'server': 'https://bogdanbuta.atlassian.net' }
    proxies={}

jira = JIRA(options=jira_options, basic_auth=(user, token), proxies=proxies)

def add_to_log_file(query_base, filter_base, file_base):
    '''Adds a list of JIRA issues to a log file, given the base query, base
    filter and base file names.

    Arguments:
        query_base {string} -- The base string for the query.
        filter_base {string} -- The base name for the filter.
        file_base {string} -- The base name for the file.
    '''
    minor = "0"
    if args.minor:
        minor = args.minor
    file = '/opt/release/{}-{}-{}'.format(file_base, args.version, minor)
    if not os.path.exists(file):
        prefix = "Project = GENNA "
        query_string = '{} {}'.format(prefix, query_base)
        filter_string = 'UOMT-v{}{}-{}'.format(args.version, filter_base, minor)
#        jira_filter = jira.create_filter(name=filter_string, description=None,
#                                         jql=query_string, favourite=None)

        print('{} filter is {}'.format(filter_base, jira_filter.viewUrl))

        with open(file, 'w') as sprint:
            sprint.write(jira_filter.viewUrl)


try:
    last_release_date = "2023/03/01"
    cur_release_date = dt.datetime.today().strftime('%Y/%m/%d')
    query_base = ('(status changed to Done during ("{}", "{}") OR '
                    'status changed to Resolved during ("{}", "{}") AND resolution = Fixed)'
                      .format(last_release_date, cur_release_date, last_release_date, cur_release_date))
    # -- generate sprint filter
    #add_to_log_file(query_base, '-All-Tickets', 'sprint')

    # -- set bugs in sprint to integrated
    # -- 81 is the id for 'Integrate Issue' status
    fixtype = 'Bug'
    query = ('project = GENNA AND issuetype = "{}" AND (resolution = Done'.format(fixtype)+
                ' OR status = Resolved) ORDER BY component ASC')
    
    results = jira.search_issues(query, maxResults=300)
    for issue in results:
        jira.transition_issue(
                issue, TO_INTEGRATED, comment='Integrated by Jira API'),
                #fixVersions=[{'name': 'TEST'}])
        jira.add_comment(issue.key, 'Integrated by Jira API')
        print(('{0} --- The issue with key {1} has been changed to'
                ' integrated').format(dt.datetime.utcnow(),
                                        issue.key))
    
#   for issue in results:
#        try:
#            m +=1
#            issue.update(fields={COMMENT: component_fix_value[m]})
#            print(str(issue) + " OK")
#        except  Exception as e:
#            print(str(issue) + " FAIL: " + str(e))

except JIRAError as e:
    print('Error while processing request')
    print(e)

sys.exit(SUCCESS)
