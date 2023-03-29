import subprocess
import re
import yaml
import boto3
import datetime
import dateutil

regionlist = [
    'us-east-1',
    'us-east-2',
    'us-west-2',
    'global'
]

max_days_before_expiration = 90

def fix_expirationdate_tags(regions):
    regions = [region for region in regions if region != "global"]
    for region in regions:
        tagging = boto3.client("resourcegroupstaggingapi", region_name = region)
        resource_tags = tagging.get_resources(TagFilters = [{"Key": "expirationdate"}])
        for resource in resource_tags["ResourceTagMappingList"]:
            write_expirationdate_tag(region, resource["ResourceARN"], resource["Tags"][0]["Value"], max_days_before_expiration)

def write_expirationdate_tag(region, resourcearn, expirationdate, maxdays):
    tagging_client = boto3.client("resourcegroupstaggingapi", region_name = region)
    maxdate = datetime.datetime.now() + dateutil.relativedelta.relativedelta(days = +maxdays)

    try:
        expirationdate = dateutil.parser.parse(expirationdate)
    except dateutil.parser.ParserError:
        expirationdate = datetime.datetime.now()

    if expirationdate > maxdate:
        tag_date = maxdate.strftime(r"%Y-%m-%d")
    else:
        tag_date = expirationdate.strftime(r"%Y-%m-%d")
    tagging_client.tag_resources(ResourceARNList = [resourcearn], Tags = {"expirationdate": tag_date})

def write_aws_nuke_config(account, regions, filter_list):
    filter_config_file_map = {
        "control-tower": "control-tower-filter.yml",
        "aws-nuke": "aws-nuke-filter.yml",
        "sso": "sso-filter.yml",
        "tagging": "/tmp/tagging-filter.yml"
    }

    presets = {}
    for filter_item in filter_list:
        with open(filter_config_file_map[filter_item]) as config_file:
            presets[filter_item] = yaml.safe_load(config_file)

    config = {
        "account-blocklist": ["000000000000"],
        "regions": regions,
        "accounts": {
            account: {
                "presets": filter_list
            }
        },
        "presets": presets
    }

    with open("/tmp/aws-nuke-config.yml", "w") as outputfile:
        yaml.dump(config, outputfile)

def write_tag_filter(resources):
    config = {
        "filters": {}
    }

    for resource in resources:
        if resource not in config["filters"]:
            config["filters"][resource] = []
        config["filters"][resource].append({
            "property": "tag:expirationdate",
            "type": "dateOlderThan",
            "value": 0
        })

    with open("/tmp/tagging-filter.yml", "w") as tagging_config_file:
        yaml.dump(config, tagging_config_file)

def parse_nuke_output(output, filter_action = None):
    resources = {}
    pattern = re.compile(r"(.+?)\s-\s(.+?)\s-\s(.+?)\s-\s(?:\[.+?]\s-\s)?(.+?)$")
    for line in output.split("\n"):
        match = pattern.match(line.strip())
        if match:
            region, resource_type, resource_id, action = match.groups()
            if filter_action == None or action == filter_action:
                if resource_type not in resources:
                    resources[resource_type] = []
                resources[resource_type].append({
                    "id": resource_id,
                    "region": region,
                    "action": action
                })
    return resources

def lambda_handler(event, context):
    aws_account_id = context.invoked_function_arn.split(":")[4]
    fix_expirationdate_tags(regionlist)
    write_aws_nuke_config(aws_account_id, regionlist, ["control-tower", "aws-nuke", "sso"])
    aws_nuke_dryrun = subprocess.check_output(["/opt/aws-nuke","--config","/tmp/aws-nuke-config.yml","--force","--force-sleep","0"])
    print(aws_nuke_dryrun.decode())
    nuke_output_parsed = parse_nuke_output(aws_nuke_dryrun.decode(), "would remove")
    write_tag_filter(list(nuke_output_parsed.keys()))
    write_aws_nuke_config(aws_account_id, regionlist, ["control-tower", "aws-nuke", "sso", "tagging"])
    subprocess.run(["/opt/aws-nuke","--config","/tmp/aws-nuke-config.yml","--force","--force-sleep","3","--no-dry-run"])
    return 0
