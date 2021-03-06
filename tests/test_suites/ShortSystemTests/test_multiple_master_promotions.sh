timeout_set '2 minutes'

metaservers_nr=5
MASTERSERVERS=$metaservers_nr \
	USE_RAMDISK="YES" \
	CHUNKSERVER_EXTRA_CONFIG="MASTER_RECONNECTION_DELAY = 1" \
	MFSEXPORTS_EXTRA_OPTIONS="allcanchangequota" \
	MOUNT_EXTRA_CONFIG="mfsacl,mfscachemode=NEVER"
	setup_local_empty_lizardfs info

wait_for_shadow_to_run_and_sync() {
	shadow_id=$1
	assert_eventually 'test -e "${info[master${shadow_id}_data_path]}/metadata.mfs.lock"'
	assert_eventually 'test -e "${info[master${shadow_id}_data_path]}/changelog.mfs.3"'
}

# Start shadow masters
for ((shadow_id=1 ; shadow_id<metaservers_nr; ++shadow_id)); do
	lizardfs_master_n $shadow_id start
	wait_for_shadow_to_run_and_sync $shadow_id
done

for ((loop_nr=0 ; loop_nr<$((2 * metaservers_nr)); ++loop_nr)); do
	touch "${info[mount0]}"/"master=$loop_nr"
	metadata=$(metadata_print "${info[mount0]}")

	prev_master_id=$((loop_nr % metaservers_nr))
	new_master_id=$(((loop_nr + 1) % metaservers_nr))

	# Kill the previous master
	lizardfs_master_daemon kill
	lizardfs_make_conf_for_shadow $prev_master_id

	# Promote a next master
	lizardfs_make_conf_for_master $new_master_id
	lizardfs_master_daemon reload

	# Demote previous master to shadow
	lizardfs_make_conf_for_shadow $prev_master_id
	lizardfs_master_n $prev_master_id start
	wait_for_shadow_to_run_and_sync $prev_master_id

	lizardfs_wait_for_all_ready_chunkservers

	MESSAGE="Data missmatch after switching masters $prev_master_id -> $new_master_id" \
			assert_no_diff "$metadata" "$(metadata_print "${info[mount0]}")"
done
