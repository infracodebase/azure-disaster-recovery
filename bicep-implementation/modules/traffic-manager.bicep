// Traffic Manager Module - Creates global load balancing and failover

metadata description = 'Creates Azure Traffic Manager for global load balancing and disaster recovery'

// Parameters
@description('Project name for resource naming')
param projectName string

@description('Environment name')
param environment string

@description('Primary endpoint resource ID')
param primaryEndpointResourceId string

@description('Secondary endpoint resource ID')
param secondaryEndpointResourceId string

@description('Resource tags')
param tags object

// Traffic Manager Profile
resource trafficManagerProfile 'Microsoft.Network/trafficManagerProfiles@2022-04-01' = {
  name: '${projectName}-${environment}-tm'
  location: 'global'
  tags: tags
  properties: {
    profileStatus: 'Enabled'
    trafficRoutingMethod: 'Priority'
    dnsConfig: {
      relativeName: '${projectName}-${environment}'
      ttl: 60
    }
    monitorConfig: {
      protocol: 'HTTPS'
      port: 443
      path: '/health'
      intervalInSeconds: 30
      timeoutInSeconds: 10
      toleratedNumberOfFailures: 3
    }
    endpoints: [
      {
        name: '${projectName}-${environment}-primary'
        type: 'Microsoft.Network/trafficManagerProfiles/azureEndpoints'
        properties: {
          targetResourceId: primaryEndpointResourceId
          priority: 1
          weight: 100
          endpointStatus: 'Enabled'
        }
      }
      {
        name: '${projectName}-${environment}-secondary'
        type: 'Microsoft.Network/trafficManagerProfiles/azureEndpoints'
        properties: {
          targetResourceId: secondaryEndpointResourceId
          priority: 2
          weight: 100
          endpointStatus: 'Enabled'
        }
      }
    ]
  }
}

// Outputs
output profileId string = trafficManagerProfile.id
output profileName string = trafficManagerProfile.name
output fqdn string = trafficManagerProfile.properties.dnsConfig.fqdn