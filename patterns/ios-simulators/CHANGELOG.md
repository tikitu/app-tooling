# ios-simulators changelog

## Unreleased

First version (draft). `mk/ios-simulators.mk`: `make ios-sims` creates the
project's own simulators, on the newest iOS and on the phone's;
`IOS_SIM_BUILD_FLAGS` builds for any simulator, signed to run locally;
`IOS_SIM_UDID` finds a simulator by name for the project's targets. Applied
in one existing iOS app after an Xcode 27 update: tests on iOS 27.0 and
26.5, and the app launched on both.
