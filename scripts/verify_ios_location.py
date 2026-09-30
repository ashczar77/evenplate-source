"""Verify that a release app does not bundle OneSignal's unused location module."""

import argparse
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("app", type=Path, help="Path to Runner.app")
    args = parser.parse_args()

    frameworks = args.app / "Frameworks"
    if not frameworks.is_dir():
        parser.error(f"Missing app frameworks directory: {frameworks}")

    location = frameworks / "OneSignalLocation.framework"
    if location.exists():
        parser.exit(
            1,
            "OneSignalLocation.framework is still bundled. Re-resolve Swift "
            "packages with ONESIGNAL_DISABLE_LOCATION=true before archiving.\n",
        )

    print(f"Verified: no OneSignalLocation.framework in {args.app}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
