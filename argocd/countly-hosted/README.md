# Countly-Hosted Argo Bootstrap

This path is the Countly-managed GitOps lane.

It is intentionally separate from the public self-hosted Argo flow under `argocd/`.

## What It Does

- reads hosted customer metadata from the private `countly-deployment` repository
- deploys shared charts from the public `helm` repository
- combines public profiles with private customer value files through Argo CD multi-source applications

## Repository Split

- public `helm` repository
  - charts
  - profiles
  - this hosted bootstrap
- private `countly-deployment` repository
  - `customers/*.yaml`
  - `environments/<customer>/...`

## Why This Exists

This keeps:

- shared product code public
- customer inventory private
- the hosted deployment path separate from the public self-hosted path

## Main Entry Point

- `root-application.yaml`

Point a bootstrap `Application` at `argocd/countly-hosted` when Argo CD should manage Countly-hosted customers.
