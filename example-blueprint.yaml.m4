include(example-macros.m4)dnl
tosca_definitions_version: cloudify_dsl_1_3

description: >
  This is example Blueprint to show how to interact with FedCloud OCCI and Puppet.

imports:
  - http://getcloudify.org/spec/cloudify/4.0m4/types.yaml
  #- http://getcloudify.org/spec/cloudify/3.3.1/types.yaml
  - http://getcloudify.org/spec/fabric-plugin/1.3.1/plugin.yaml
  - http://getcloudify.org/spec/diamond-plugin/1.3.1/plugin.yaml
  - https://raw.githubusercontent.com/vholer/cloudify-occi-plugin-experimental/master/plugin.yaml
  - types/puppet.yaml
  - types/dbms.yaml
  - types/server.yaml
  - types/webserver.yaml

inputs:
  # OCCI
  occi_endpoint:
    default: ''
    type: string
  occi_auth:
    default: ''
    type: string
  occi_username:
    default: ''
    type: string
  occi_password:
    default: ''
    type: string
  occi_user_cred:
    default: ''
    type: string
  occi_ca_path:
    default: ''
    type: string
  occi_voms:
    default: False
    type: boolean

  # contextualization
  cc_username:
    default: cfy
    type: string
  cc_public_key:
    type: string
  cc_private_key_filename:
    type: string
  cc_data:
    default: {}

  # VM parameters
  os_tpl:
    type: string
  resource_tpl:
    type: string
  os_availability_zone:
    type: string
  worker_os_tpl:
    type: string
  worker_resource_tpl:
    type: string
  worker_availability_zone:
    type: string
  worker_scratch_size:
    type: integer


dsl_definitions:
  occi_configuration: &occi_configuration
    endpoint: { get_input: occi_endpoint }
    auth: { get_input: occi_auth }
    username: { get_input: occi_username }
    password: { get_input: occi_password }
    user_cred: { get_input: occi_user_cred }
    ca_path: { get_input: occi_ca_path }
    voms: { get_input: occi_voms }

  cloud_configuration: &cloud_configuration
    username: { get_input: cc_username }
    public_key: { get_input: cc_public_key }
    data: { get_input: cc_data }

  fabric_env: &fabric_env
    user: { get_input: cc_username }
    key_filename: { get_input: cc_private_key_filename }

  agent_configuration: &agent_configuration
    install_method: remote
    user: { get_input: cc_username }
    key: { get_input: cc_private_key_filename }

  puppet_config: &puppet_config
    repo: 'https://yum.puppetlabs.com/puppetlabs-release-pc1-el-7.noarch.rpm'
    package: 'puppet-agent'
    download: resources/puppet.tar.gz

node_templates:
  apacheNode:
    type: _NODE_SERVER_
    properties:
      name: 'Cloudify example web node'
      resource_config:
        os_tpl: { get_input: os_tpl }
        resource_tpl: { get_input: resource_tpl }
        availability_zone: { get_input: os_availability_zone }
      agent_config: *agent_configuration
      cloud_config: *cloud_configuration
      occi_config: *occi_configuration
      fabric_env:
        <<: *fabric_env
        host_string: { get_attribute: [apacheNode, ip] } # req. by relationship ref.


  apache:
    type: _NODE_WEBSERVER_
    instances:
      deploy: 1
    properties:
      fabric_env:
        <<: *fabric_env
        host_string: { get_attribute: [apacheNode, ip] }
      puppet_config:
        <<: *puppet_config
        manifests:
          start: manifests/apache.pp
    relationships:
      - type: cloudify.relationships.contained_in
        target: apacheNode


  torqueServer:
    type: _NODE_WEBSERVER_ #TODO
    instances:
      deploy: 1
    properties:
      fabric_env: *fabric_env
      puppet_config:
        <<: *puppet_config
        manifests:
          start: manifests/torque_server.pp
    relationships:
      - type: cloudify.relationships.contained_in
        target: apacheNode

#

  workerNode:
    type: _NODE_SERVER_
    properties:
      name: 'Worker node'
      resource_config:
        os_tpl: { get_input: worker_os_tpl }
        resource_tpl: { get_input: worker_resource_tpl }
        availability_zone: { get_input: worker_availability_zone }
      agent_config: *agent_configuration
      cloud_config: *cloud_configuration
      occi_config: *occi_configuration
      fabric_env: *fabric_env
#     capabilities:
#       scalable:
#         properties:
#           default_instances: 2
#           min_instances: 0
#           max_instances: 5


  torqueMom:
    type: _NODE_WEBSERVER_ #TODO
    instances:
      deploy: 1
    properties:
      fabric_env: *fabric_env
      puppet_config:
        <<: *puppet_config
        manifests:
          start: manifests/torque_mom.pp
        hiera:
          westlife::volume::device: /dev/vdc
          westlife::volume::fstype: ext4
          westlife::volume::mountpoint: /scratch
          westlife::volume::mode: '1777'
    relationships:
      - type: cloudify.relationships.contained_in
        target: workerNode
      - type: example.relationships.puppet.connected_to
        target: torqueServer
        source_interfaces:
          cloudify.interfaces.relationship_lifecycle:
            postconfigure:
              inputs:
                manifest: manifests/torque_mom.pp     # nastaveni jmena/np mom na serveru
        target_interfaces:
          cloudify.interfaces.relationship_lifecycle:
            preconfigure:
              inputs:
                manifest: manifests/torque_server.pp  # nastaveni ::torque_sever_name
            establish:
              inputs:
                manifest: manifests/torque_server.pp  # rekonfigurace serveru

groups:
  workerNodes:
    members: [workerNode]

policies:
  scaleWorkerNodes:
    type: cloudify.policies.scaling
    properties:
      default_instances: 1
    targets: [workerNodes]


outputs:
  endpoint:
    description: Web application endpoint
    value:
      url: { concat: ['http://', { get_attribute: [apacheNode, ip] }] }


# vim: set syntax=yaml
