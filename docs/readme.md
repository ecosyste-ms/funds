# Ecosystem Funds

## Overview

Funds are based on either a package manager for a software ecosystem (i.e. rubygems, npm or cargo), or from a [featured topic on GitHub](https://awesome.ecosyste.ms/topics). The funds are used to support the development of the ecosystem, and are distributed to maintainers, contributors, and projects in the ecosystem.

## Funding

Each fund has an associated Project on Open Collective, which is used to collect and distribute funds. Donations can be made to the fund, and the funds are automatically distributed to maintainers, contributors, and projects in the ecosystem based on their usage and criticality within their ecosystem.

Data is synced into the funds from Open Collective, triggered by webhooks. Project data is synced from [Ecosyste.ms](https://ecosyste.ms/) on a daily bases, and transaction data is synced in real-time.

Funding is allocated on a monthly basis once a minimum threshold is reached, funding sources are discovered and then payouts made to maintainers, contributors, and projects in the ecosystem.

## Allocations

The list of possible projects in a fund is fed into the allocation algorithm which uses three main factors to determine the allocation of funds:

- downloads
- dependent_repos
- dependent_packages

The algorithm is designed to reward projects that are widely used, have a large number of dependent projects, and are critical to the ecosystem.

These numbers are normalized and then used to determine the allocation of funds to each project, weighted scores are calculated based on the three normalized factors, and then the funds are allocated proportionally based on the weighted scores.

Each allocation has a default minimum amount, currently at $50.00, which is the minimum amount that can be allocated to a project, and a default set of weights for each factor, which can be adjusted based on the fund.

Results of the allocations are then displayed on the fund page, and the funds are distributed to the projects based on the allocations.

## Payouts

Once the funds have been allocated to the projects, we search for a funding source for each project. Starting with the funding urls we can find from the metadata of the open source project. These can be in the form of a donation link, a patreon link, or a link to a funding platform like Open Collective. 

Funding urls can come from:
- package metadata
- repository metadata
- funding.yml file
- readme file
- repository owner metadata (github sponsors)

We also have a list of approved funding domains that can accept donations:

- opencollective.com
- github.com/sponsors
- patreon.com
- liberapay.com
- ko-fi.com
- funding.communitybridge.org
- buymeacoffee.com

There is a priority order for funding sources, starting with the most preferred funding source, Open Collective, and then moving down the list. This is to try to minimize the fees that are taken out of the donations and speed up the process of getting the funds to the maintainers.

Open Collective projects are also split by which host they use, opencollective.com/opensource or others, as the fees can are different for each host, and for projects hosted on opencollective.com/opensource there are no fees to transfer between collectives.

For non-Open Collective funding sources, we create a proxy collective on open collective, this acts as a gateway to donate to that funding source through open collective, where the open collective back office can group together transactions to the same platform and make a single transfer, both minimizing costs and retaining transparency of where the money was sent, even if the hosting platform does not have an open ledger like Open Collective.

If a project does not have any funding links, we attempt to find a contact email and send an automated expense invitation through open collective, which will allow the project to claim the funds.

If we cannot find a funding source or contact email, we do not include the project in the allocation process. We are working on ways to improve this process, and are looking for ways to automate the process of finding funding sources for projects.

## Expense Invitations

When an invite is sent, we set up a webhook to listen for if the invite is accepted or rejected. If the invite is accepted, we mark the project as having received the funds, and if the invite is rejected, we mark the project as not having received the funds and also not to send the money again in the future.