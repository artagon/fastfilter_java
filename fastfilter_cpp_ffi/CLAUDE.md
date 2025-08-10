1. Failures: https://github.com/artagon/fastfilter_java/actions/runs/16865569947/
2. Windows build failing with  "C:\Program Files\Git\bin\git.exe" checkout --progress --force -B master refs/remotes/origin/master
   Error: error: invalid path 'fastfilter_cpp_ffi/fastfilter_ffi_java/src/main/resources/native-library-config-windows-x86_64.properties '
   Error: The process 'C:\Program Files\Git\bin\git.exe' failed with exit code 128
3. Build native all platforms Run bazelbuild/setup-bazelisk@v2
   Attempting to download v1.22.1...
   Acquiring v1.22.1 from https://github.com/bazelbuild/bazelisk/releases/download/v1.22.1/bazelisk-linux-amd64
   Adding to the cache ...
   Successfully cached bazelisk to /opt/hostedtoolcache/bazelisk/1.22.1/x64
   Added bazelisk to the path
4. OSX  Trying to resolve the latest version from remote
   Resolved latest version as 24.0.2+12
   Trying to download...
   Downloading Java 24.0.2+12 (Temurin-Hotspot) from https://github.com/adoptium/temurin24-binaries/releases/download/jdk-24.0.2%2B12/OpenJDK24U-jdk_aarch64_mac_hotspot_24.0.2_12.tar.gz ...
   Error: The operation was canceled.
5. Ubuntu: Run bazelbuild/setup-bazelisk@v2
   Attempting to download v1.22.1...
   Acquiring v1.22.1 from https://github.com/bazelbuild/bazelisk/releases/download/v1.22.1/bazelisk-linux-amd64
   Adding to the cache ...
   Successfully cached bazelisk to /opt/hostedtoolcache/bazelisk/1.22.1/x64
   Added bazelisk to the path
   Error: Cache service responded with 400
6. Java Failed [INFO] ------------------------------------------------------------------------
   Error:  Failed to execute goal on project jmh: Could not collect dependencies for project io.github.fastfilter:jmh:jar:1.0.3-SNAPSHOT
   Error:  Failed to read artifact descriptor for io.github.fastfilter:fastfilter:jar:1.0.3-SNAPSHOT
   Error:  	Caused by: The following artifacts could not be resolved: io.github.fastfilter:fastfilter:pom:1.0.3-SNAPSHOT (absent): Could not transfer artifact io.github.fastfilter:fastfilter:pom:1.0.3-SNAPSHOT from/to github (https://maven.pkg.github.com/FastFilter/fastfilter_java): status code: 401, reason phrase: Unauthorized (401)
   Error:  -> [Help 1]
   Error:  
   Error:  To see the full stack trace of the errors, re-run Maven with the -e switch.
   Error:  Re-run Maven using the -X switch to enable full debug logging.
   Error:  
   Error:  For more information about the errors and possible solutions, please read the following articles:
   Error:  [Help 1] http://cwiki.apache.org/confluence/display/MAVEN/DependencyResolutionException