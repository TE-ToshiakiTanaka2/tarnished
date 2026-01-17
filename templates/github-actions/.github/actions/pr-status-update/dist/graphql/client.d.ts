/**
 * GraphQL client wrapper for GitHub API
 */
export declare class GraphQLClient {
    private client;
    constructor(token: string);
    /**
     * Execute a GraphQL query
     */
    query<T>(query: string, variables: Record<string, unknown>): Promise<T>;
    /**
     * Execute a GraphQL mutation
     */
    mutate<T>(mutation: string, variables: Record<string, unknown>): Promise<T>;
}
//# sourceMappingURL=client.d.ts.map