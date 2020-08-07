#!/usr/bin/env bash

# This script based on sources from moby repo here: https://github.com/moby/moby.git
set -eo pipefail
# check if essential commands are in our PATH
for cmd in curl jq host ; do
	if ! command -v $cmd &> /dev/null; then
		echo >&2 "error: '$cmd' not found!"
		exit 1
	fi
done

usage() {
	echo "usage: $0 dir image[:tag][@digest] ..."
	echo "       $0 /tmp/old-hello-world hello-world:latest@sha256:8be990ef2aeb16dbcb9271ddfe2610fa6658d13f6dfb8bc72074cc1ca36966a7"
	[ -z "$1" ] || exit "$1"
}

dir="$1" # dir for building tar in
shift || usage 1 >&2

[ $# -gt 0 -a "$dir" ] || usage 2 >&2
mkdir -p "$dir"

# hacky workarounds for Bash 3 support (no associative arrays)
images=()
rm -f "$dir"/tags-*.tmp
manifestJsonEntries=()
doNotGenerateManifestJson=
# repositories[busybox]='"latest": "...", "ubuntu-14.04": "..."'

# bash v4 on Windows CI requires CRLF separator
newlineIFS=$'\n'

# We consider what came to us in DEPLOYER_CONTAINER_REGISTRY as a URL. We select hostname from
# it and try to make DNS resolve.
# If such a domain name does not exist, it means that we were given a namespace for the docker
# hub repository - we use what was passed as a namespace.
# If such a domain name exists, we divide it by / into the domain name plus port and docker namespace.
# We refer by the given name with the given namespace to a registry other than the docker hub.

url=$DEPLOYER_CONTAINER_REGISTRY

IFS=':' read -ra url_array <<< $url

if [[ ${#url_array[@]} -gt 1 ]] ; then
  host=${url_array[0]}
else
  IFS='/' read -ra url_array <<< $url
  if [[ ${#url_array[@]} -gt 1 ]] ; then
    host=${url_array[0]}
  else
    host=$url
  fi
fi

# if ishost is true - passed registry other than default dockerhub
# if ishost is false - passed namespace - and we will use default dockerhub registry
ishost=true
namespace=""
registry_url=""

command host ${host} ||  getent hosts ${host} || ishost=false
if [[ $ishost == true ]] ; then
        IFS='/' read -ra host_port <<< $url
        registry_url=${host_port[0]}
        if [[ ${#host_port[@]} -gt 1 ]] ; then
                namespace=${host_port[1]}/
        fi
else
        namespace=${host}/
fi

echo ishost = $ishost namespace = $namespace registry_url = $registry_url

# Passed namespace on registry.docker.io
if [[ $ishost == false ]] ; then
  registryBase='https://registry-1.docker.io'
  authBase='https://auth.docker.io'
  authService='registry.docker.io'
# Passed the other registry than registry.docker.io
else
  registryBase="http://${registry_url}"
fi


# https://github.com/moby/moby/issues/33700
fetch_blob() {
	local token="$1"
	shift
	local image="$1"
	shift
	local digest="$1"
	shift
	local targetFile="$1"
	shift
	local curlArgs=("$@")

    local auth_header=""
    if [[ $token != 777 ]] ; then
      auth_header="-H \"Authorization: Bearer $token\""
    fi

    curlString="curl -s -S "${curlArgs[@]}" \
			$auth_header \
			"$registryBase/v2/$image/blobs/$digest" \
			-o "$targetFile" \
			-D-"

	local curlHeaders="$(eval $curlString)"
	curlHeaders="$(echo "$curlHeaders" | tr -d '\r')"
	if grep -qE "^HTTP/[0-9].[0-9] 3" <<< "$curlHeaders"; then
		rm -f "$targetFile"

		local blobRedirect="$(echo "$curlHeaders" | awk -F ': ' 'tolower($1) == "location" { print $2; exit }')"
		if [ -z "$blobRedirect" ]; then
			echo >&2 "error: failed fetching '$image' blob '$digest'"
			echo "$curlHeaders" | head -1 >&2
			return 1
		fi

		curl -fSL "${curlArgs[@]}" \
			"$blobRedirect" \
			-o "$targetFile"
	fi
}

# handle 'application/vnd.docker.distribution.manifest.v2+json' manifest
handle_single_manifest_v2() {
	local manifestJson="$1"
	shift

	local configDigest="$(echo "$manifestJson" | jq --raw-output '.config.digest')"
	local imageId="${configDigest#*:}" # strip off "sha256:"

	local configFile="$imageId.json"
	fetch_blob "$token" "$image" "$configDigest" "$dir/$configFile" -s

	local layersFs="$(echo "$manifestJson" | jq --raw-output --compact-output '.layers[]')"
	local IFS="$newlineIFS"
	local layers=($layersFs)
	unset IFS

	echo "Downloading '$imageIdentifier' (${#layers[@]} layers)..."
	local layerId=
	local layerFiles=()
	for i in "${!layers[@]}"; do
		local layerMeta="${layers[$i]}"

		local layerMediaType="$(echo "$layerMeta" | jq --raw-output '.mediaType')"
		local layerDigest="$(echo "$layerMeta" | jq --raw-output '.digest')"

		# save the previous layer's ID
		local parentId="$layerId"
		# create a new fake layer ID based on this layer's digest and the previous layer's fake ID
		layerId="$(echo "$parentId"$'\n'"$layerDigest" | sha256sum | cut -d' ' -f1)"
		# this accounts for the possibility that an image contains the same layer twice (and thus has a duplicate digest value)

		mkdir -p "$dir/$layerId"
		echo '1.0' > "$dir/$layerId/VERSION"

		if [ ! -s "$dir/$layerId/json" ]; then
			local parentJson="$(printf ', parent: "%s"' "$parentId")"
			local addJson="$(printf '{ id: "%s"%s }' "$layerId" "${parentId:+$parentJson}")"
			# this starter JSON is taken directly from Docker's own "docker save" output for unimportant layers
			jq "$addJson + ." > "$dir/$layerId/json" <<- 'EOJSON'
				{
					"created": "0001-01-01T00:00:00Z",
					"container_config": {
						"Hostname": "",
						"Domainname": "",
						"User": "",
						"AttachStdin": false,
						"AttachStdout": false,
						"AttachStderr": false,
						"Tty": false,
						"OpenStdin": false,
						"StdinOnce": false,
						"Env": null,
						"Cmd": null,
						"Image": "",
						"Volumes": null,
						"WorkingDir": "",
						"Entrypoint": null,
						"OnBuild": null,
						"Labels": null
					}
				}
			EOJSON
		fi

		case "$layerMediaType" in
			application/vnd.docker.image.rootfs.diff.tar.gzip)
				local layerTar="$layerId/layer.tar"
				layerFiles=("${layerFiles[@]}" "$layerTar")
				# TODO figure out why "-C -" doesn't work here
				# "curl: (33) HTTP server doesn't seem to support byte ranges. Cannot resume."
				# "HTTP/1.1 416 Requested Range Not Satisfiable"
				if [ -f "$dir/$layerTar" ]; then
					# TODO hackpatch for no -C support :'(
					echo "skipping existing ${layerId:0:12}"
					continue
				fi

				local token=777
				if [[ $ishost == false ]] ; then
				  token="$(curl -fsSL "$authBase/token?service=$authService&scope=repository:$namespace$image:pull" | jq --raw-output '.token')"
				fi

				fetch_blob "$token" "${namespace}${image}" "$layerDigest" "$dir/$layerTar" --progress
				;;

			*)
				echo >&2 "error: unknown layer mediaType ($imageIdentifier, $layerDigest): '$layerMediaType'"
				exit 1ls
				;;
		esac
	done

	# change "$imageId" to be the ID of the last layer we added (needed for old-style "repositories" file which is created later -- specifically for older Docker daemons)
	imageId="$layerId"

	# munge the top layer image manifest to have the appropriate image configuration for older daemons
	local imageOldConfig="$(jq --raw-output --compact-output '{ id: .id } + if .parent then { parent: .parent } else {} end' "$dir/$imageId/json")"
	jq --raw-output "$imageOldConfig + del(.history, .rootfs)" "$dir/$configFile" > "$dir/$imageId/json"

	local manifestJsonEntry="$(
		echo '{}' | jq --raw-output '. + {
			Config: "'"$configFile"'",
			RepoTags: ["'"${image#library\/}:$tag"'"],
			Layers: '"$(echo '[]' | jq --raw-output ".$(for layerFile in "${layerFiles[@]}"; do echo " + [ \"$layerFile\" ]"; done)")"'
		}'
	)"
	manifestJsonEntries=("${manifestJsonEntries[@]}" "$manifestJsonEntry")
}

while [ $# -gt 0 ]; do
	imageTag="$1"
	shift
	image="${imageTag%%[:@]*}"
	imageTag="${imageTag#*:}"
	digest="${imageTag##*@}"
	tag="${imageTag%%@*}"

	imageFile="${image//\//_}" # "/" can't be in filenames :)

    auth_header=""

	token=777
    if [[ $ishost == false ]] ; then
	   token="$(curl -fsSL "$authBase/token?service=$authService&scope=repository:$namespace$image:pull" | jq --raw-output '.token')"
       auth_header="-H \"Authorization: Bearer $token\""
    fi

    curlStr="curl -fsSL \
			$auth_header \
			-H \"Accept: application/vnd.docker.distribution.manifest.v2+json\" \
			-H \"Accept: application/vnd.docker.distribution.manifest.list.v2+json\" \
			-H \"Accept: application/vnd.docker.distribution.manifest.v1+json\" \
			$registryBase/v2/$namespace$image/manifests/$digest"
    manifestJson=$(eval $curlStr)

	if [ "${manifestJson:0:1}" != '{' ]; then
		echo >&2 "error: /v2/$image/manifests/$digest returned something unexpected:"
		echo >&2 "  $manifestJson"
		exit 1
	fi

	imageIdentifier="$image:$tag@$digest"

	handle_single_manifest_v2 "$manifestJson"

	echo

	if [ -s "$dir/tags-$imageFile.tmp" ]; then
		echo -n ', ' >> "$dir/tags-$imageFile.tmp"
	else
		images=("${images[@]}" "$image")
	fi
	echo -n '"'"$tag"'": "'"$imageId"'"' >> "$dir/tags-$imageFile.tmp"
done

echo -n '{' > "$dir/repositories"
firstImage=1
for image in "${images[@]}"; do
	imageFile="${image//\//_}" # "/" can't be in filenames :)
	image="${image#library\/}"

	[ "$firstImage" ] || echo -n ',' >> "$dir/repositories"
	firstImage=
	echo -n $'\n\t' >> "$dir/repositories"
	echo -n '"'"$image"'": { '"$(cat "$dir/tags-$imageFile.tmp")"' }' >> "$dir/repositories"
done
echo -n $'\n}\n' >> "$dir/repositories"

rm -f "$dir"/tags-*.tmp

if [ -z "$doNotGenerateManifestJson" ] && [ "${#manifestJsonEntries[@]}" -gt 0 ]; then
	echo '[]' | jq --raw-output ".$(for entry in "${manifestJsonEntries[@]}"; do echo " + [ $entry ]"; done)" > "$dir/manifest.json"
else
	rm -f "$dir/manifest.json"
fi


echo "Download of images into '$dir' complete."
echo "Use something like the following to load the result into a Docker daemon:"
echo "  tar -cC '$dir' . | docker load"
