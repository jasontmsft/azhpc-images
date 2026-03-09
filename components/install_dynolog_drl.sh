#!/bin/bash
##############################################################################
# Build and install dynolog and dyno-relay-logger
##############################################################################

set -ex
source ${UTILS_DIR}/utilities.sh

DYNOLOG_INSTALL_DIR=/opt/dynolog/bin
mkdir -p $DYNOLOG_INSTALL_DIR

dynolog_metadata=$(get_component_config "dynolog")
DYNOLOG_VERSION=$(jq -r '.version' <<< $dynolog_metadata)
DYNOLOG_URL=$(jq -r '.url' <<< $dynolog_metadata)

drl_metadata=$(get_component_config "dyno_relay_logger")
DRL_VERSION=$(jq -r '.version' <<< $drl_metadata)
DRL_URL=$(jq -r '.url' <<< $drl_metadata)

##############################################################################
# Install build dependencies
##############################################################################
if [[ $DISTRIBUTION == "azurelinux3.0" ]]; then
    tdnf install -y cmake cargo ninja-build build-essential
    source $HOME/.cargo/env
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
elif [[ $DISTRIBUTION == *"ubuntu"* ]]; then
    apt install -y cmake cargo ninja-build build-essential 
    apt install -y g++ pkg-config uuid-dev libssl-dev
    source $HOME/.cargo/env
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
elif [[ $DISTRIBUTION == almalinux* ]] || [[ $DISTRIBUTION == rocky* ]]; then
    yum install -y cmake cargo ninja-build
    source $HOME/.cargo/env
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
fi

##############################################################################
# Build and install dynolog
##############################################################################
git clone --recurse-submodules -j8 $DYNOLOG_URL /tmp/dynolog
pushd /tmp/dynolog
./scripts/build.sh -DCMAKE_POLICY_VERSION_MINIMUM=3.5
cp build/dynolog/src/dynolog $DYNOLOG_INSTALL_DIR
cp build/release/dyno $DYNOLOG_INSTALL_DIR
popd
rm -rf /tmp/dynolog

cat <<-EOF > /etc/systemd/system/dynolog.service
[Unit]
Description=dynolog
After=nvidia-dcgm.service

[Service]
Environment="GLOG_logtostderr=1" "GLOG_minloglevel=2"
ExecStart=/opt/dynolog/bin/dynolog -enable_ipc_monitor=true -enable_gpu_monitor=true -kernel_monitor_reporting_interval_s=10 -dcgm_lib_path=/usr/lib/libdcgm.so -dcgm_reporting_interval_s=10 -use_udsrelay=true -dcgm_fields="100,155,204,1001,1002,1003,1004,1005,1006,1007,1008,1009,1010,1011,1012"
Restart=always
RestartSec=60s
User=root
Group=root
WorkingDirectory=/tmp

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable dynolog.service

##############################################################################
# Build and install dyno-relay-logger
##############################################################################
git clone --recurse-submodules -j8 $DRL_URL /tmp/dyno-relay-logger
pushd /tmp/dyno-relay-logger
mkdir build && cd build
cmake .. -DCMAKE_POLICY_VERSION_MINIMUM=3.5
cmake --build . -j$(nproc)
cp dynorelaylogger dynorelayloggerinfo $DYNOLOG_INSTALL_DIR
popd
rm -rf /tmp/dyno-relay-logger

cat <<-EOF > /etc/systemd/system/dyno-relay-logger.service
[Unit]
Description=dyno-relay-logger
After=nvidia-dcgm.service

[Service]
Environment="GLOG_logtostderr=1" "GLOG_minloglevel=2"
ExecStart=/opt/dynolog/bin/dynorelaylogger --forward=aehubs
Restart=always
RestartSec=60s
User=root
Group=root
WorkingDirectory=/tmp

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable dyno-relay-logger.service

write_component_version "dynolog" ${DYNOLOG_VERSION}
write_component_version "dyno_relay_logger" ${DRL_VERSION}
