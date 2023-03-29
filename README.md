# terraform-aws-nuke

This code can be used to deploy a lambda function and associated resources to run [aws-nuke](https://github.com/rebuy-de/aws-nuke)

## Dependencies

There are two dependencies that you need to setup prior to running the Terraform configuration files.

- pyyaml
- aws-nuke

### pyyaml

From the root of the repo, run the following command using python version 3.9:
```Python
python -m pip install --target=./dependencies/pyyaml/python
```

### aws-nuke

Download the arm64 package from a [release of aws-nuke](https://github.com/rebuy-de/aws-nuke/releases). Extract the aws-nuke executable to the dependencies/aws-nuke directory and rename the file to `aws-nuke`.
