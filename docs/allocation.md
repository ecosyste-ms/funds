# How Funding is Allocated

The purpose of this algorithm is to fairly distribute available funds among projects based on their importance and critical usage, using metrics like downloads and dependencies.

## Core of the Algorithm

### 1. Gather Project Data

We evaluate each project using the following key metrics:

- **Downloads**: Number of times the project has been downloaded.
- **Dependent Repositories**: Number of repositories that rely on this project.
- **Dependent Packages**: Number of packages that depend on this project.

These metrics help identify the most critical and widely used projects.

### 2. Normalize the Data

To make fair comparisons, we adjust all metrics to a common scale (from `0` to `1`). This process, called normalization, prevents any single metric from dominating the calculation due to larger raw values.

### 3. Calculate a Score for Each Project

We determine a score for each project using a weighted formula:

- Downloads, dependent repositories, and dependent packages are each assigned a weight (e.g., 20% each).
- The score is calculated by combining these weighted metrics.

For example:

\[
\text{Score} = (\text{Downloads} \times 0.2) + (\text{Dependent Repositories} \times 0.2) + (\text{Dependent Packages} \times 0.2)
\]

This score represents the project’s importance and is used to determine its share of the funds.

### 4. Allocate Funds Based on Scores

Each project receives a portion of the total available funds based on its score:

\[
\text{Funding Amount} = \left(\frac{\text{Project Score}}{\text{Total Score of All Projects}}\right) \times \text{Total Funds}
\]

Projects with higher scores, indicating they are more critical, receive a larger share of the funds.

### 5. Handle Minimum Funding Threshold

If the calculated funding for a project is below a certain minimum threshold, it is considered too small to be useful. In these cases:

- The project does not receive any funds.
- The unallocated amount is added back to a pool of leftover funds.

### 6. Redistribute Leftover Funds

The leftover funds are redistributed among projects that met the minimum funding threshold. This ensures that all available funds are utilized effectively.

### 7. Ecosystem Flexibility

This approach is designed to work across various ecosystems of different shapes and sizes. By using normalized metrics and adjustable weights, the algorithm adapts to the unique characteristics of each ecosystem, ensuring fair allocation regardless of project scale or ecosystem diversity.

## Why This Approach?

This algorithm aims to:

- **Support Critical Projects**: Projects that are heavily used or depended upon by others are prioritized for funding.
- **Ensure Fairness**: By normalizing the data, the algorithm avoids favoring any single metric disproportionately.
- **Maximize Fund Utilization**: Projects receiving less than the minimum allocation are skipped, and leftover funds are redistributed, preventing waste.
- **Adapt Across Ecosystems**: The method scales well to different ecosystems, accommodating variations in project size, usage patterns, and available metrics.

This method ensures that the most impactful projects receive the necessary support across a wide range of ecosystems.