import * as core from '@actions/core';
import { graphql } from '@octokit/graphql';

/**
 * GraphQL client wrapper for GitHub API
 */
export class GraphQLClient {
  private client: typeof graphql;

  constructor(token: string) {
    this.client = graphql.defaults({
      headers: {
        authorization: `token ${token}`,
      },
    });
  }

  /**
   * Execute a GraphQL query
   */
  async query<T>(query: string, variables: Record<string, unknown>): Promise<T> {
    core.debug(`Executing GraphQL query with variables: ${JSON.stringify(variables)}`);

    try {
      const response = await this.client<T>(query, variables);
      return response;
    } catch (error) {
      if (error instanceof Error) {
        core.error(`GraphQL query failed: ${error.message}`);
        throw error;
      }
      throw new Error('Unknown GraphQL error');
    }
  }

  /**
   * Execute a GraphQL mutation
   */
  async mutate<T>(mutation: string, variables: Record<string, unknown>): Promise<T> {
    core.debug(`Executing GraphQL mutation with variables: ${JSON.stringify(variables)}`);

    try {
      const response = await this.client<T>(mutation, variables);
      return response;
    } catch (error) {
      if (error instanceof Error) {
        core.error(`GraphQL mutation failed: ${error.message}`);
        throw error;
      }
      throw new Error('Unknown GraphQL error');
    }
  }
}
