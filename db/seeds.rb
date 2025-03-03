funds = [
  {
    name: 'Ruby',
    slug: 'ruby',
    description: "Fund for the most critical ruby packages on rubygems.org",
    registry_name: "rubygems.org",
    featured: true
  },
  {
    name: 'JavaScript',
    slug: 'javascript',
    description: "Fund for the most critical javascript packages on npmjs.com",
    registry_name: "npmjs.org",
    featured: true
  },
  {
    name: 'Python',
    slug: 'python',
    description: "Fund for the most critical python packages on pypi.org",
    registry_name: "pypi.org",
    featured: true
  },
  {
    name: 'Java',
    slug: 'java',
    description: "Fund for the most critical java packages on maven.org",
    registry_name: "repo1.maven.org"
  },
  {
    name: 'PHP',
    slug: 'php',
    description: "Fund for the most critical php packages on packagist.org",
    registry_name: "packagist.org"
  },
  {
    name: 'Rust',
    slug: 'rust',
    description: "Fund for the most critical rust packages on crates.io",
    registry_name: "crates.io",
    featured: true
  },
  {
    name: 'Go',
    slug: 'go',
    description: "Fund for the most critical go packages on proxy.golang.org",
    registry_name: "proxy.golang.org"
  },
  {
    name: 'Swift',
    slug: 'swift',
    description: "Fund for the most critical swift packages on swiftpackageindex.com",
    registry_name: "swiftpackageindex.com"
  },
  {
    name: 'Dart',
    slug: 'dart',
    description: "Fund for the most critical dart packages on pub.dev",
    registry_name: "pub.dev"
  },
  {
    name: 'Elixir',
    slug: 'elixir',
    description: "Fund for the most critical elixir packages on hex.pm",
    registry_name: "hex.pm"
  },
  {
    name: 'Haskell',
    slug: 'haskell',
    description: "Fund for the most critical haskell packages on hackage.haskell.org",
    registry_name: "hackage.haskell.org"
  },
  {
    name: 'Django',
    slug: 'django',
    description: "Fund for the most critical django packages on pypi.org",
    featured: true
  }
]

funds.each do |fund|
  f = Fund.find_or_create_by(slug: fund[:slug]) 
  f.name = fund[:name]
  f.description = fund[:description]
  f.registry_name = fund[:registry_name]
  f.featured = fund[:featured] || false
  f.save

end

f = Fund.find_by!(slug: 'ruby')

Transaction.create({
  fund: f,
  transaction_type: 'CREDIT',
  transaction_kind: 'CONTRIBUTION',
  amount: 16800,
  currency: 'USD',
  uuid: SecureRandom.uuid,
  order: {
    legacyId: '1'
  },
  account_name: 'Sentry',
  account_image_url: 'https://opencollective.com/sentry/logo.png',
  account: 'sentry',
})

Transaction.create({
  fund: f,
  transaction_type: 'CREDIT',
  transaction_kind: 'CONTRIBUTION',
  amount: 10000,
  currency: 'USD',
  uuid: SecureRandom.uuid,
  order: {
    legacyId: '2'
  },
  account_name: 'Google',
  account_image_url: 'https://opencollective.com/google/logo.png',
  account: 'google',
})

Transaction.create({
  fund: f,
  transaction_type: 'CREDIT',
  transaction_kind: 'CONTRIBUTION',
  amount: 10000,
  currency: 'USD',
  uuid: SecureRandom.uuid,
  order: {
    legacyId: '2'
  },
  account_name: 'Google',
  account_image_url: 'https://opencollective.com/google/logo.png',
  account: 'google',
})

Transaction.create({
  fund: f,
  transaction_type: 'CREDIT',
  transaction_kind: 'CONTRIBUTION',
  amount: 10000,
  currency: 'USD',
  uuid: SecureRandom.uuid,
  order: {
    legacyId: '3'
  },
  account_name: 'Svelte',
  account_image_url: 'https://opencollective.com/svelte/logo.png',
  account: 'svelte',
})