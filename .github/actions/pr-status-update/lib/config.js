import * as fs from "node:fs";
import * as core from "@actions/core";
import * as yaml from "js-yaml";
/**
 * Load and validate configuration from YAML file
 */
export function loadConfig(configPath) {
    core.info(`Loading configuration from: ${configPath}`);
    if (!fs.existsSync(configPath)) {
        throw new Error(`Configuration file not found: ${configPath}`);
    }
    const content = fs.readFileSync(configPath, "utf8");
    const config = yaml.load(content);
    return validateConfig(config);
}
/**
 * Validate configuration object
 */
export function validateConfig(config) {
    if (!config || typeof config !== "object") {
        throw new Error("Configuration must be an object");
    }
    const cfg = config;
    // Validate project section
    if (!cfg.project || typeof cfg.project !== "object") {
        throw new Error('Configuration must have a "project" section');
    }
    const project = cfg.project;
    // Validate project.type
    if (project.type !== "organization" && project.type !== "user") {
        throw new Error('project.type must be "organization" or "user"');
    }
    // Validate project.owner
    if (typeof project.owner !== "string" || project.owner.length === 0) {
        throw new Error("project.owner must be a non-empty string");
    }
    // Validate project.number
    if (typeof project.number !== "number" || project.number <= 0) {
        throw new Error("project.number must be a positive number");
    }
    // Validate defaults (optional)
    const defaults = cfg.defaults;
    if (defaults !== undefined) {
        if (typeof defaults !== "object" || defaults === null) {
            throw new Error("defaults must be an object");
        }
        const defaultsObj = defaults;
        for (const [key, value] of Object.entries(defaultsObj)) {
            if (typeof value !== "string" && typeof value !== "number") {
                throw new Error(`defaults.${key} must be a string or number`);
            }
        }
    }
    // Validate pr section (optional)
    const pr = cfg.pr;
    let prConfig;
    if (pr !== undefined) {
        if (typeof pr !== "object" || pr === null) {
            throw new Error("pr must be an object");
        }
        const prObj = pr;
        // Validate pr.status (required if pr section exists)
        if (typeof prObj.status !== "string" || prObj.status.length === 0) {
            throw new Error("pr.status must be a non-empty string");
        }
        // Validate pr.branch_pattern (optional)
        if (prObj.branch_pattern !== undefined) {
            if (typeof prObj.branch_pattern !== "string") {
                throw new Error("pr.branch_pattern must be a string");
            }
            // Validate that it's a valid regex
            try {
                new RegExp(prObj.branch_pattern);
            }
            catch {
                throw new Error("pr.branch_pattern must be a valid regular expression");
            }
        }
        prConfig = {
            status: prObj.status,
            branch_pattern: prObj.branch_pattern,
        };
    }
    return {
        project: {
            type: project.type,
            owner: project.owner,
            number: project.number,
        },
        defaults: defaults,
        pr: prConfig,
    };
}
//# sourceMappingURL=config.js.map