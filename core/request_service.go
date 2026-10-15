package main

type requestTunIdentity struct {
	serviceID  string
	generation uint64
}

func stopOwnedRequestService(expected, current requestTunIdentity, stopTun func()) bool {
	if expected.serviceID == "" || expected.generation == 0 || expected != current {
		return false
	}
	stopTun()
	if isRunning.Load() {
		handleStopListener()
	}
	return true
}
