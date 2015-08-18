numactl --hardware

nova aggregate-create aggregate0 zone0
nova aggregate-set-metadata aggregate0 pinned=true

nova aggregate-add-host aggregate0 compute-0-0.local

nova flavor-delete m1_1.large.cpu.pin
nova flavor-delete m1_2.large.cpu.pin

nova flavor-create m1_1.large.cpu.pin 11 65536 160 14
nova flavor-create m1_2.large.cpu.pin 12 65536 160 14

nova flavor-key m1_1.large.cpu.pin set cpu:cpuset=2,3,4,5,6,7,16,17,18,19,20,21,22,23
nova flavor-key m1_2.large.cpu.pin set cpu:cpuset=10,11,12,13,14,15,24,25,26,27,28,29,30,31

nova flavor-key m1_1.large.cpu.pin set "aggregate_instance_extra_specs:pinned"="true"
nova flavor-key m1_2.large.cpu.pin set "aggregate_instance_extra_specs:pinned"="true"


