#!/usr/bin/env bash

# Copyright 2020 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -eEuo pipefail

ROOT="$(cd "$(dirname "$0")/.." &>/dev/null; pwd -P)"
SOURCE_DIRS="cmd internal tools"


echo "🌳 Set up environment variables"
eval $(${ROOT}/scripts/dev init)


echo "🚒 Verify Protobufs are up to date"
set +e
${ROOT}/scripts/gen_protos.sh
# Don't verify the *.pb.go files here as we tidy these. Verify after format.
set -e


echo "🧽 Verify goimports formattting"
set +e
which goimports >/dev/null 2>&1
if [ $? -ne 0 ]; then
   echo "✋ No 'goimports' found. Please use"
   echo "✋   go get golang.org/x/tools/cmd/goimports"
   echo "✋ to enable import cleanup. Import cleanup skipped."
else
   echo "🧽 Format with goimports"
   goimports -w $(echo $SOURCE_DIRS)
   # Check if there were uncommited changes.
   # Ignore comment line changes as sometimes proto gen just updates versions
   # of the generator
   git diff -G'(^\s+[^/])' *.go | tee /dev/stderr | (! read)
   if [ $? -ne 0 ]; then
      echo "✋ Found uncommited changes after goimports."
      echo "✋ Commit these changes before merging."
      exit 1
   fi
fi
set -e


echo "🧹 Verify gofmt format"
set +e
diff -u <(echo -n) <(gofmt -d -s .)
git diff -G'(^\s+[^/])' *.go | tee /dev/stderr | (! read)
if [ $? -ne 0 ]; then
   echo "✋ Found uncommited changes after gofmt."
   echo "✋ Commit these changes before merging."
   exit 1
fi
set -e


echo "🌌 Go mod verify"
set +e
go mod verify
if [ $? -ne 0 ]; then
   echo "✋ go mod verify failed."
   exit 1
fi
set -e

# Fail if a dependency was added without the necessary go.mod/go.sum change
# being part of the commit.
echo "🌌 Go mod tidy"
set +e
go mod tidy;
git diff go.mod | tee /dev/stderr | (! read)
if [ $? -ne 0 ]; then
   echo "✋ Found uncommited go.mod changes after go mod tidy."
   exit 1
fi
git diff go.sum | tee /dev/stderr | (! read)
if [ $? -ne 0 ]; then
   echo "✋ Found uncommited go.sum changes after go mod tidy."
   exit 1
fi
set -e

# TODO: Add this back in once a few outstanding failures are handled
# echo "Running 'go vet'..."
# set -x
# go vet ./...
# set +x


echo "🚧 Compile"
go build ./...


echo "🧪 Test"
DB_USER= DB_NAME= DB_PASSWORD= go test ./... -coverprofile=coverage.out


echo "🧪 Test DB Tests"
if [ "${CI:-}" == "true" ]; then
   echo "🚒 In CI Container, start postgres process"
   export DB_USER="postgres"
   export DB_PASSWORD="mypassword"
   export DB_SSLMODE="disable"

   service postgresql start
fi

if [ "${DB_USER:-}" == "false" ]; then
   echo "🚨 DB_USER is not configured. Test DB tests will not run."
fi
go test ./internal/database -coverprofile=coverage.out

echo "🧑‍🔬 Test Coverage"
go tool cover -func coverage.out | grep total | awk '{print $NF}'
