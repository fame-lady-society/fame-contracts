import fs from "fs";
import path from "path";

/**
 * Get all file names in a folder recursively
 * @param {string} folderPath - Path to the folder
 * @returns {string[]} - Array of file paths
 */
function getAllFiles(folderPath) {
  let filesList = [];

  // Read the contents of the folder
  const items = fs.readdirSync(folderPath);

  items.forEach((item) => {
    const fullPath = path.join(folderPath, item);
    if (fs.statSync(fullPath).isDirectory()) {
      // Recursively add files from subdirectories
      filesList = filesList.concat(getAllFiles(fullPath));
    } else {
      filesList.push(fullPath);
    }
  });

  return filesList;
}

/**
 * Compare two folders and return differences
 * @param {string[]} folder1Files - Array of file paths from folder 1
 * @param {string[]} folder2Files - Array of file paths from folder 2
 * @returns {Object} - Object with files only in folder 1 and only in folder 2
 */
function compareFolders(folder1Files, folder2Files) {
  const folder1Set = new Set(folder1Files);
  const folder2Set = new Set(folder2Files);

  const onlyInFolder1 = [...folder1Set].filter((file) => !folder2Set.has(file));
  const onlyInFolder2 = [...folder2Set].filter((file) => !folder1Set.has(file));

  return {
    onlyInFolder1,
    onlyInFolder2,
  };
}

// Paths to the two folders to compare
const folder1Path = ".metadata/staging-metadata-new";
const folder2Path = ".metadata/staging-metadata";

// Get all files from both folders
const folder1Files = getAllFiles(folder1Path).map((file) =>
  path.relative(folder1Path, file)
);
const folder2Files = getAllFiles(folder2Path).map((file) =>
  path.relative(folder2Path, file)
);

// Compare the folders
const differences = compareFolders(folder1Files, folder2Files);

// Output the differences
console.log("Files only in folder 1:", differences.onlyInFolder1);
console.log("Files only in folder 2:", differences.onlyInFolder2);
