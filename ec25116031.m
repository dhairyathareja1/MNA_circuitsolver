function result = ec25116031(fileName)
%{ 
    Simple DC circuit solver using Modified Nodal Analysis (MNA).

 Netlist format (one element per line):
   Rname  n+  n-  resistance
   Iname  n+  n-  current
   Vname  n+  n-  voltage
   Gname  n+  n-  nc+ nc- transconductance   (VCCS)
   Ename  n+  n-  nc+ nc- voltage_gain       (VCVS)
   Fname  n+  n-  Vcontrol current_gain      (CCCS)
   Hname  n+  n-  Vcontrol transresistance   (CCVS)
   Oname  out ref noninv inv                 (ideal op-amp)

 Node 0/gnd/ground = ground. Current flows n+ to n-.

 For F and H elements, Vcontrol must be the name of an independent voltage source. A zero-volt voltage source may be used to sense current. 
 %}

    txt = fileread(fileName);
    lines = regexp(txt, '\r\n|\n|\r', 'split');

    els = struct('name', {}, 'type', {}, 'nodes', {}, 'value', {}, 'control', {});

    % Parse each line into an element struct.
    for ln = 1:numel(lines)
        line = strtrim(lines{ln});
        if isempty(line) || line(1) == '*' || line(1) == '#'
            continue;
        end

        cPos = regexp(line, '[#%]', 'once');   % strip inline comment
        if ~isempty(cPos)
            line = strtrim(line(1:cPos - 1));
        end
        if isempty(line)
            continue;
        end
        if strcmpi(line, '.end')
            break;
        elseif line(1) == '.'
            continue;
        end

        w = regexp(line, '\s+', 'split');
        t = upper(w{1}(1));

        e.name = upper(w{1});
        e.type = t;
        e.nodes = {};
        e.value = 0;
        e.control = '';

        switch t
            case {'R', 'I', 'V'}
                e.nodes = w(2:3);
                e.value = str2double(w{4});

            case {'G', 'E'}
                e.nodes = w(2:5);
                e.value = str2double(w{6});

            case {'F', 'H'}
                e.nodes = w(2:3);
                e.control = upper(w{4});
                e.value = str2double(w{5});

            case 'O'
                e.nodes = w(2:5);
        end

        els(end + 1) = e; %#ok<AGROW>
    end

    nodeNames = {};
    nodeMap = containers.Map('KeyType', 'char', 'ValueType', 'double');

    for k = 1:numel(els)
        for j = 1:numel(els(k).nodes)
            nd = normNode(els(k).nodes{j});
            els(k).nodes{j} = nd;
            if ~strcmp(nd, '0') && ~isKey(nodeMap, nd)
                nodeNames{end + 1} = nd; %#ok<AGROW>
                nodeMap(nd) = numel(nodeNames);
            end
        end
    end

    numNodes = numel(nodeNames);
    if numNodes > 40
        error('The circuit has %d non-ground nodes; the maximum is 40.', numNodes);
    end

    % V/E/H/O elements each add one branch-current unknown
    curMap = containers.Map('KeyType', 'char', 'ValueType', 'double');
    curNames = {};

    %{ Tracks only independent V sources, so F/H can be use this instead of curMap (which also holds E/H/O current indices).%}
    vSourceMap = containers.Map('KeyType', 'char', 'ValueType', 'double');

    for k = 1:numel(els)
        if any(strcmp(els(k).type, {'V', 'E', 'H', 'O'}))
            curNames{end + 1} = els(k).name; %#ok<AGROW>
            curMap(els(k).name) = numNodes + numel(curNames);
        end
        if strcmp(els(k).type, 'V')
            vSourceMap(els(k).name) = curMap(els(k).name);
        end
    end

    N = numNodes + numel(curNames);
    A = zeros(N, N);
    z = zeros(N, 1);

    % Add each element into A*x = z.
    for k = 1:numel(els)
        it = els(k);
        n = zeros(1, numel(it.nodes));
        for j = 1:numel(it.nodes)
            n(j) = nodeNum(nodeMap, it.nodes{j});
        end

        switch it.type
            case 'R'
                g = 1 / it.value;
                A = stamp2(A, n(1), n(2), g);

            case 'I'
                z = addZ(z, n(1), -it.value);
                z = addZ(z, n(2),  it.value);

            case 'V'
                q = curMap(it.name);
                A = stampBranch(A, n(1), n(2), q);
                z(q) = it.value;

            case 'G'                     % VCCS
                g = it.value;
                A = addA(A, n(1), n(3),  g);
                A = addA(A, n(1), n(4), -g);
                A = addA(A, n(2), n(3), -g);
                A = addA(A, n(2), n(4),  g);

            case 'E'                     % VCVS
                q = curMap(it.name);
                gain = it.value;
                A = stampBranch(A, n(1), n(2), q);
                A = addA(A, q, n(3), -gain);
                A = addA(A, q, n(4),  gain);

            case 'F'                     % CCCS
                if ~isKey(vSourceMap, it.control)
                    error(['%s is controlled by "%s", but F must be ' ...
                           'controlled by an independent V source.'], ...
                          it.name, it.control);
                end
                qc = vSourceMap(it.control);
                gain = it.value;
                A = addA(A, n(1), qc,  gain);
                A = addA(A, n(2), qc, -gain);

            case 'H'                     % CCVS
                q = curMap(it.name);
                if ~isKey(vSourceMap, it.control)
                    error(['%s is controlled by "%s", but H must be ' ...
                           'controlled by an independent V source.'], ...
                          it.name, it.control);
                end
                qc = vSourceMap(it.control);
                A = stampBranch(A, n(1), n(2), q);
                A(q, qc) = A(q, qc) - it.value;

            case 'O'                     % Ideal op-amp
                q = curMap(it.name);
                A = addA(A, n(1), q,  1);
                A = addA(A, n(2), q, -1);
                A = addA(A, q, n(3),  1);
                A = addA(A, q, n(4), -1);
        end
    end

    x = A \ z;

    fprintf('\nNode voltages\n');
    fprintf('-------------\n');
    fprintf('V(0) = 0 V\n');
    for k = 1:numNodes
        fprintf('V(%s) = %.10g V\n', nodeNames{k}, x(k));
    end

    fprintf('\nExtra MNA currents (positive from n+ to n-)\n');
    fprintf('-------------------------------------------\n');
    if isempty(curNames)
        fprintf('(none)\n');
    else
        for k = 1:numel(curNames)
            idx = numNodes + k;
            fprintf('I(%s) = %.10g A\n', curNames{k}, x(idx));
        end
    end

    result.nodeNames = nodeNames;
    result.nodeVoltages = x(1:numNodes);
    result.currentNames = curNames;
    result.currentValues = x(numNodes + 1:end);
    result.A = A;
    result.z = z;
    result.x = x;
end


function nd = normNode(nd)
    nd = lower(nd);
    if strcmp(nd, 'gnd') || strcmp(nd, 'ground')
        nd = '0';
    end
end

function num = nodeNum(nodeMap, nd)
    if strcmp(nd, '0')
        num = 0;
    else
        num = nodeMap(nd);
    end
end

function M = stamp2(M, p, m, val)
    M = addA(M, p, p,  val);
    M = addA(M, p, m, -val);
    M = addA(M, m, p, -val);
    M = addA(M, m, m,  val);
end

function M = stampBranch(M, p, m, qi)
    M = addA(M, p, qi,  1);
    M = addA(M, m, qi, -1);
    M = addA(M, qi, p,  1);
    M = addA(M, qi, m, -1);
end

function v = addZ(v, row, val)
    if row ~= 0
        v(row) = v(row) + val;
    end
end

function M = addA(M, row, col, val)
    if row ~= 0 && col ~= 0            % ground (index 0) gets no entry
        M(row, col) = M(row, col) + val;
    end
end