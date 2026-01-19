import * as core from "@actions/core";
import { graphql } from "@octokit/graphql";
/**
 * GraphQL client wrapper for GitHub API
 */
export class GraphQLClient {
    client;
    constructor(token) {
        this.client = graphql.defaults({
            headers: {
                authorization: `token ${token}`,
            },
        });
    }
    /**
     * Execute a GraphQL query
     */
    async query(query, variables) {
        core.debug(`Executing GraphQL query with variables: ${JSON.stringify(variables)}`);
        try {
            const response = await this.client(query, variables);
            return response;
        }
        catch (error) {
            if (error instanceof Error) {
                core.error(`GraphQL query failed: ${error.message}`);
                throw error;
            }
            throw new Error("Unknown GraphQL error");
        }
    }
    /**
     * Execute a GraphQL mutation
     */
    async mutate(mutation, variables) {
        core.debug(`Executing GraphQL mutation with variables: ${JSON.stringify(variables)}`);
        try {
            const response = await this.client(mutation, variables);
            return response;
        }
        catch (error) {
            if (error instanceof Error) {
                core.error(`GraphQL mutation failed: ${error.message}`);
                throw error;
            }
            throw new Error("Unknown GraphQL error");
        }
    }
}
//# sourceMappingURL=client.js.map