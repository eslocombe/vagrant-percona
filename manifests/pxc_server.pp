include stdlib 

include base::hostname
include base::packages
include base::insecure
include base::swappiness

include percona::repository
include percona::toolkit
include percona::sysbench

include percona::cluster::client
include percona::cluster::server
include percona::cluster::config
include percona::cluster::service
include percona::cluster::sstuser
include percona::cluster::clustercheckuser

include misc::myq_gadgets
include misc::myq_tools

include test::user

if $datadir_dev and $datadir_dev != '' {
	class { 'mysql::datadir':
		datadir_dev => $datadir_dev,
		datadir_dev_scheduler => $datadir_dev_scheduler,
		datadir_fs => $datadir_fs,
		datadir_fs_opts => $datadir_fs_opts,
		datadir_mkfs_opts => $datadir_mkfs_opts
	}

	Class['mysql::datadir'] -> Class['percona::cluster::server']

	if $softraid == 'true' {
		class { 'misc::softraid':
			softraid_dev => $softraid_dev,
			softraid_level => $softraid_level,
			softraid_devices => $softraid_devices,
			softraid_dev_str => $softraid_dev_str
		}

		Class['misc::softraid'] -> Class['mysql::datadir']
	}
}


Class['percona::repository'] -> Class['percona::cluster::client'] -> Class['percona::cluster::server'] -> Class['percona::cluster::config'] -> Class['percona::cluster::service'] -> Class['percona::cluster::sstuser'] -> Class['percona::cluster::clustercheckuser']

Class['base::packages'] -> Class['misc::myq_gadgets']
Class['base::packages'] -> Class['misc::myq_tools']

Class['base::packages'] -> Class['percona::repository']
Class['base::insecure'] -> Class['percona::repository']

Class['percona::repository'] -> Class['percona::toolkit']
Class['percona::repository'] -> Class['percona::sysbench']

Class['percona::cluster::client'] -> Class['percona::toolkit']

Class['percona::cluster::service'] -> Class['test::user']

if $sysbench_load == 'true' {
	class { 'test::sysbench_load':
		schema => $schema,
		tables => $tables,
		rows => $rows,
		threads => $threads,
		engine => $engine
	}
	
	Class['percona::cluster::client'] -> Class['percona::sysbench']
	Class['percona::sysbench'] -> Class['test::sysbench_load']
	Class['test::user'] -> Class['test::sysbench_load']
}

if $enable_consul == 'true' {
	info( 'enabling consul agent' )
	
	$config_hash = delete_undef_values( {
        'datacenter'  => $datacenter,
        'data_dir'    => '/opt/consul',
        'log_level'   => 'INFO',
        'node_name'   => $node_name ? {
            undef => $vagrant_hostname,
            default => $node_name
        },
        'bind_addr'   => $default_interface ? {
            undef => undef,
            default => getvar("ipaddress_${default_interface}")
            },
        'client_addr' => '0.0.0.0',
	})
	
	
	class { 'consul':
		join_cluster => $join_cluster,
	    config_hash => $config_hash
	}

	include consul::local_dns
	
	# do local_dns well before percona::service so it has time to finish loading
	Class['consul::local_dns'] -> Class['percona::cluster::config'] 
	Class['consul'] -> Class['percona::cluster::config']

}

if ( $percona_agent_api_key ) {
	include percona::agent
    
    Class['percona::cluster::service'] -> Class['percona::agent']
}

if ( $vividcortex_api_key ) {
	class { 'misc::vividcortex':
		api_key => $vividcortex_api_key
	}
    
    Class['percona::cluster::service'] -> Class['misc::vividcortex']
}

if $sysbench_skip_test_client != 'true' {
    include test::sysbench_test_script
}

