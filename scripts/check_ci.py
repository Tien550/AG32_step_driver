#!/usr/bin/env python3
"""
check_ci.py - Quick CI/CD status monitor for AG32 Stepper Driver repository
"""

import urllib.request
import json
import sys

def main():
    repo = "Tien550/AG32_step_driver"
    url = f"https://api.github.com/repos/{repo}/actions/runs?per_page=3"
    req = urllib.request.Request(url, headers={"User-Agent": "CI-Monitor"})
    
    try:
        with urllib.request.urlopen(req) as resp:
            data = json.loads(resp.read().decode())
            runs = data.get("workflow_runs", [])
            if not runs:
                print("No workflow runs found.")
                return 0
            
            latest = runs[0]
            print(f"Workflow Run #{latest['run_number']} (Commit: {latest['head_sha'][:7]} - '{latest['head_commit']['message'].splitlines()[0]}')")
            print(f"Status: {latest['status'].upper()} | Conclusion: {str(latest['conclusion']).upper()}")
            
            jobs_url = latest.get("jobs_url")
            if jobs_url:
                j_req = urllib.request.Request(jobs_url, headers={"User-Agent": "CI-Monitor"})
                with urllib.request.urlopen(j_req) as j_resp:
                    j_data = json.loads(j_resp.read().decode())
                    print("\nJobs Status:")
                    for job in j_data.get("jobs", []):
                        icon = "PASS" if job["conclusion"] == "success" else (job["conclusion"] or job["status"])
                        print(f"  [{icon:8s}] {job['name']}")
    except Exception as err:
        print(f"Error querying GitHub API: {err}")
        return 1
    return 0

if __name__ == "__main__":
    sys.exit(main())
